param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$errors = [System.Collections.Generic.List[string]]::new()

function Read-File([string]$RelativePath) {
    $path = Join-Path $RepositoryRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        $errors.Add("Missing $RelativePath")
        return ''
    }
    return Get-Content -Raw -Encoding utf8 -LiteralPath $path
}

function Require-Pattern(
    [string]$Content,
    [string]$Pattern,
    [string]$Message
) {
    if ($Content -notmatch $Pattern) {
        $errors.Add($Message)
    }
}

function Read-PlistString(
    [string]$RelativePath,
    [string]$Key
) {
    $path = Join-Path $RepositoryRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $errors.Add("Missing $RelativePath")
        return ''
    }
    try {
        [xml]$plist = Get-Content -Raw -Encoding utf8 -LiteralPath $path
        $elements = @($plist.plist.dict.ChildNodes | Where-Object { $_.NodeType -eq 'Element' })
        for ($index = 0; $index -lt $elements.Count - 1; $index += 1) {
            if ($elements[$index].Name -eq 'key' -and $elements[$index].InnerText -eq $Key) {
                return $elements[$index + 1].InnerText
            }
        }
        $errors.Add("$RelativePath does not contain $Key.")
    } catch {
        $errors.Add("$RelativePath is not a valid plist XML document: $($_.Exception.Message)")
    }
    return ''
}

$project = Read-File 'project.yml'
$releaseDocumentation = Read-File 'docs/release-configuration.md'
$privacyWebsiteReplacement = Read-File 'docs/privacy-policy-website-replacement.md'
$privacyDataInventory = Read-File 'docs/app-store-privacy-data-inventory.md'
$appleReleaseChecklist = Read-File 'docs/apple-release-checklist.md'
$languagePrivacy = Read-File 'Resources/Privacy/Language/PrivacyInfo.xcprivacy'
$localPrivacy = Read-File 'Resources/Privacy/LocalOnly/PrivacyInfo.xcprivacy'
$firebaseIntegration = Read-File 'Sources/FirebaseRecordsIntegration.swift'
$gitIgnore = Read-File '.gitignore'
$targetBodies = @{}

$canonicalBundleConfigurations = @(
    @{ Target = 'MinikPlus'; Setting = 'MINIK_PLUS_BUNDLE_IDENTIFIER'; Identifier = 'com.appsbybros.minik.plus' },
    @{ Target = 'MinikPlusEnglish'; Setting = 'MINIK_PLUS_ENGLISH_BUNDLE_IDENTIFIER'; Identifier = 'com.appsbybros.minik.plus.english' },
    @{ Target = 'MinikMathPlus'; Setting = 'MINIK_MATH_PLUS_BUNDLE_IDENTIFIER'; Identifier = 'com.appsbybros.minik.math.plus' },
    @{ Target = 'MinikMath'; Setting = 'MINIK_MATH_BUNDLE_IDENTIFIER'; Identifier = 'com.appsbybros.minik.math' },
    @{ Target = 'MinikPingPong'; Setting = 'MINIK_PING_PONG_BUNDLE_IDENTIFIER'; Identifier = 'com.appsbybros.minik.pingpong' },
    @{ Target = 'ProductConfigurationTests'; Setting = 'MINIK_TESTS_BUNDLE_IDENTIFIER'; Identifier = 'com.appsbybros.minik.tests' }
)
foreach ($configuration in $canonicalBundleConfigurations) {
    $target = $configuration.Target
    $setting = $configuration.Setting
    $identifier = $configuration.Identifier
    $targetMatch = [regex]::Match(
        $project,
        "(?ms)^  $([regex]::Escape($target)):\s*\r?\n(?<body>.*?)(?=^  [A-Za-z][A-Za-z0-9]*:\s*\r?$|^schemes:\s*\r?$)"
    )
    if (-not $targetMatch.Success) {
        $errors.Add("project.yml is missing target $target.")
        continue
    }
    $targetBody = $targetMatch.Groups['body'].Value
    $targetBodies[$target] = $targetBody
    Require-Pattern $targetBody "PRODUCT_BUNDLE_IDENTIFIER: \$\($setting\)" "$target does not route PRODUCT_BUNDLE_IDENTIFIER through $setting."
    Require-Pattern $releaseDocumentation ([regex]::Escape($setting)) "Release documentation omits $setting."
    Require-Pattern $targetBody "(?m)^\s*$([regex]::Escape($setting)): $([regex]::Escape($identifier))\s*$" "$target does not use canonical Apple identifier $identifier."
    Require-Pattern $releaseDocumentation ([regex]::Escape($identifier)) "Release documentation omits canonical Apple identifier $identifier."
}

Require-Pattern $project 'MINIK_MARKETING_VERSION: "1\.7\.9"[\s\S]*MINIK_BUILD_NUMBER: "79"[\s\S]*MARKETING_VERSION: \$\(MINIK_MARKETING_VERSION\)[\s\S]*CURRENT_PROJECT_VERSION: \$\(MINIK_BUILD_NUMBER\)' 'Established Android-aligned marketing/build version configuration is incomplete.'
Require-Pattern $project 'CFBundleShortVersionString: \$\(MARKETING_VERSION\)\s+CFBundleVersion: \$\(CURRENT_PROJECT_VERSION\)' 'Info.plist must take its version and build from the build settings; XcodeGen otherwise writes 1.0 (1).'
$forbiddenBundleIdentifierErrors = 0
foreach ($forbiddenIdentifier in @(
    'com\.example\.temporary\.',
    'com\.minik\.minik\.plus(?:\.[A-Za-z0-9._-]+)?'
)) {
    if ($project -match $forbiddenIdentifier) {
        $forbiddenBundleIdentifierErrors += 1
        $errors.Add("Shipping Apple target configuration retains forbidden bundle identifier pattern: $forbiddenIdentifier")
    }
}
Require-Pattern $project 'ASSETCATALOG_COMPILER_APPICON_NAME: \$\(MINIK_APP_ICON_NAME\)' 'App icon build-setting hook is missing.'
Require-Pattern $project 'MINIK_APP_ICON_NAME: MinikPlusAppIcon' 'MinikPlus Android-derived app icon is not selected.'
Require-Pattern $project 'MinikPlusEnglish:[\s\S]*?MINIK_APP_ICON_NAME: MinikPlusAppIcon' 'MinikPlusEnglish must share the MinikPlus launcher icon, as on Android.'
Require-Pattern $project '(?m)^  MinikMath:[\s\S]*?MINIK_APP_ICON_NAME: MinikMathAppIcon' 'MinikMath must use the MINIK Math icon (Android Minik Math app_icon.png).'
Require-Pattern $project '(?m)^  MinikMathPlus:[\s\S]*?MINIK_APP_ICON_NAME: MinikMathPlusAppIcon' 'MinikMathPlus must use the Android Minik Math Plus store icon.'
$firebaseConfigurations = @(
    @{ Target = 'MinikPlus'; Path = 'Config/Firebase/MinikPlus/GoogleService-Info.plist'; BundleID = 'com.appsbybros.minik.plus' },
    @{ Target = 'MinikPlusEnglish'; Path = 'Config/Firebase/MinikPlusEnglish/GoogleService-Info.plist'; BundleID = 'com.appsbybros.minik.plus.english' }
)
$firebasePlistMismatchErrors = 0
foreach ($configuration in $firebaseConfigurations) {
    $target = $configuration.Target
    $relativePath = $configuration.Path
    $expectedBundleID = $configuration.BundleID
    $targetBody = $targetBodies[$target]
    Require-Pattern $targetBody "MINIK_FIREBASE_PLIST_PATH: `"\$\(SRCROOT\)/$([regex]::Escape($relativePath))`"" "$target does not use only its production Firebase plist."
    Require-Pattern $targetBody 'if ! firebase_bundle_id="\$\(/usr/libexec/PlistBuddy -c ''Print :BUNDLE_ID''[\s\S]*if \[ "\$firebase_bundle_id" != "\$PRODUCT_BUNDLE_IDENTIFIER" \][\s\S]*/bin/cp "\$MINIK_FIREBASE_PLIST_PATH" "\$firebase_destination"' "$target does not validate Firebase BUNDLE_ID before injection."
    $actualBundleID = Read-PlistString $relativePath 'BUNDLE_ID'
    if ($actualBundleID -ne $expectedBundleID) {
        $firebasePlistMismatchErrors += 1
        $errors.Add("$relativePath BUNDLE_ID '$actualBundleID' does not match $target '$expectedBundleID'.")
    }
    Require-Pattern $gitIgnore "(?m)^!$([regex]::Escape($relativePath))\s*$" "$relativePath is still excluded from the canonical repository."
}
foreach ($target in @('MinikMathPlus', 'MinikMath')) {
    if ($targetBodies[$target] -match 'MINIK_FIREBASE_PLIST_PATH|GoogleService-Info\.plist|FirebaseApple') {
        $errors.Add("$target must not receive Firebase configuration or SDK products.")
    }
}
$pongPrivacy = Read-File 'Resources/Privacy/ModernPong/PrivacyInfo.xcprivacy'
Require-Pattern $targetBodies['MinikPingPong'] 'product: FirebaseDatabase' 'Modern Ping Pong RTDB dependency is missing.'
Require-Pattern $targetBodies['MinikPingPong'] 'Config/Firebase/MinikPingPong/GoogleService-Info\.plist' 'Modern Apple registration is missing.'
if ((Read-PlistString 'Config/Firebase/MinikPingPong/GoogleService-Info.plist' 'BUNDLE_ID') -ne 'com.appsbybros.minik.pingpong') { $errors.Add('Modern Firebase bundle mismatch.') }
Require-Pattern $gitIgnore '(?m)^!Config/Firebase/MinikPingPong/GoogleService-Info\.plist' 'Modern registration is excluded from version control.'
Require-Pattern $pongPrivacy 'NSPrivacyCollectedDataTypeUserID[\s\S]*NSPrivacyCollectedDataTypeGameplayContent' 'Modern online privacy categories are missing.'
Require-Pattern $pongPrivacy '<key>NSPrivacyTracking</key>\s*<false/>' 'Modern tracking must remain disabled.'
$firebaseConfigureCalls = [regex]::Matches($firebaseIntegration, 'FirebaseApp\.configure\s*\(').Count
if ($firebaseConfigureCalls -ne 1) {
    $errors.Add("Expected exactly one FirebaseApp.configure call; found $firebaseConfigureCalls.")
}
Require-Pattern $project 'Resources/Privacy/Language/PrivacyInfo\.xcprivacy' 'Language privacy manifest is not included.'
Require-Pattern $project 'Resources/Privacy/LocalOnly/PrivacyInfo\.xcprivacy' 'Local-only privacy manifest is not included.'

foreach ($privacy in @(
    @{ Name = 'Language'; Content = $languagePrivacy },
    @{ Name = 'LocalOnly'; Content = $localPrivacy }
)) {
    try {
        [void][xml]$privacy.Content
    } catch {
        $errors.Add("$($privacy.Name) PrivacyInfo.xcprivacy is not valid XML: $($_.Exception.Message)")
    }
    Require-Pattern $privacy.Content '<key>NSPrivacyTracking</key>\s*<false/>' "$($privacy.Name) privacy manifest must explicitly disable tracking."
    Require-Pattern $privacy.Content 'NSPrivacyAccessedAPICategoryUserDefaults[\s\S]*<string>CA92\.1</string>' "$($privacy.Name) privacy manifest lacks the app-only UserDefaults reason."
}

Require-Pattern $languagePrivacy 'NSPrivacyCollectedDataTypeUserID[\s\S]*NSPrivacyCollectedDataTypeGameplayContent' 'Language privacy manifest does not describe the current remote-record data categories.'
Require-Pattern $languagePrivacy 'NSPrivacyCollectedDataTypePurposeAppFunctionality' 'Language record collection lacks its app-functionality purpose.'
if ($localPrivacy -match 'NSPrivacyCollectedDataType(?:UserID|GameplayContent)') {
    $errors.Add('Math/Ping Pong local-only manifest must not claim Language Firebase collection.')
}

$sourceText = (Get-ChildItem -File -Recurse -LiteralPath (Join-Path $RepositoryRoot 'Sources') -Filter '*.swift' |
    ForEach-Object { Get-Content -Raw -Encoding utf8 -LiteralPath $_.FullName }) -join "`n"
if ($sourceText -notmatch '\bUserDefaults\b') {
    $errors.Add('Privacy audit expected app-owned UserDefaults use but found none; review manifest scope.')
}
$otherRequiredReasonAPIs = [regex]::Matches(
    $sourceText,
    '\b(systemUptime|mach_absolute_time|creationDate|modificationDate|fileModificationDate|contentModificationDateKey|creationDateKey|volumeAvailableCapacityKey|volumeAvailableCapacityForImportantUsageKey|volumeAvailableCapacityForOpportunisticUsageKey|volumeTotalCapacityKey|activeInputModes)\b'
).Count
if ($otherRequiredReasonAPIs -ne 0) {
    $errors.Add("Found $otherRequiredReasonAPIs app-owned required-reason API reference(s) outside the current UserDefaults-only manifest inventory.")
}

$iconSets = @(Get-ChildItem -Directory -Recurse -LiteralPath $RepositoryRoot -Filter '*.appiconset')
$entitlementFiles = @(Get-ChildItem -File -Recurse -LiteralPath $RepositoryRoot -Filter '*.entitlements')
if ($entitlementFiles.Count -ne 1 -or $entitlementFiles[0].Name -ne 'MinikLanguage.entitlements') {
    $errors.Add('Expected exactly the shared Language App Attest entitlement file.')
}
foreach ($target in @('MinikPlus', 'MinikPlusEnglish')) {
    Require-Pattern $targetBodies[$target] 'CODE_SIGN_ENTITLEMENTS: Resources/Entitlements/MinikLanguage\.entitlements' "$target must use the shared App Attest entitlement."
    Require-Pattern $targetBodies[$target] 'product: FirebaseAppCheck' "$target must link FirebaseAppCheck."
}
foreach ($target in @('MinikMathPlus', 'MinikMath', 'MinikPingPong')) {
    if ($targetBodies[$target] -match 'CODE_SIGN_ENTITLEMENTS|FirebaseAppCheck') {
        $errors.Add("$target must not inherit the Language App Attest capability.")
    }
}
# Like Android (sensorPortrait), the Language apps are portrait-only. XcodeGen appends
# template arrays, so the targets must :REPLACE the template's orientation lists, and
# iPad honours a restricted orientation set only for a full-screen app.
$portraitOnlyTargets = @('MinikPlus', 'MinikPlusEnglish')
foreach ($target in $portraitOnlyTargets) {
    Require-Pattern $targetBodies[$target] '(?m)^\s+UIRequiresFullScreen: true\s*$' "$target must require full screen so iPad keeps it in portrait."
    Require-Pattern $targetBodies[$target] '(?m)^\s+UISupportedInterfaceOrientations:REPLACE:\s*\r?\n\s+- UIInterfaceOrientationPortrait\s*\r?\n(?!\s*- )' "$target must replace the template's iPhone orientations with portrait only."
    Require-Pattern $targetBodies[$target] '(?m)^\s+UISupportedInterfaceOrientations~ipad:REPLACE:\s*\r?\n\s+- UIInterfaceOrientationPortrait\s*\r?\n\s+- UIInterfaceOrientationPortraitUpsideDown\s*\r?\n(?!\s*- )' "$target must replace the template's iPad orientations with the two portrait ones."
}

if ($iconSets.Count -ne 9) {
    $errors.Add("Expected exactly nine app icon sets (two Language, Math, Math Plus, Modern, Retro and Multi Ping Pong, Amudu, Splash); found $($iconSets.Count).")
}
foreach ($iconName in @('MinikPlusAppIcon', 'MinikPlusEnglishAppIcon', 'MinikMathAppIcon', 'MinikMathPlusAppIcon')) {
    $iconPath = Join-Path $RepositoryRoot "Resources\MinikVisuals.xcassets\$iconName.appiconset\$iconName-1024.png"
    if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
        $errors.Add("Missing generated Language app icon: $iconPath")
        continue
    }
    try {
        Add-Type -AssemblyName System.Drawing
        $icon = [Drawing.Bitmap]::new($iconPath)
        try {
            if ($icon.Width -ne 1024 -or $icon.Height -ne 1024) {
                $errors.Add("$iconName must be exactly 1024 by 1024 pixels.")
            }
            if (($icon.PixelFormat -band [Drawing.Imaging.PixelFormat]::Alpha) -ne 0) {
                $errors.Add("$iconName must be opaque and must not contain an alpha channel.")
            }
        } finally {
            $icon.Dispose()
        }
    } catch {
        $errors.Add("$iconName could not be decoded: $($_.Exception.Message)")
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $RepositoryRoot 'Scripts\migrate-android-app-icons.ps1') -PathType Leaf)) {
    $errors.Add('Missing deterministic Android app-icon migration script.')
}
Require-Pattern $releaseDocumentation 'docs/app-icon-provenance\.md' 'Release documentation must cite the Language icon provenance.'
Require-Pattern $releaseDocumentation 'MinikLanguage\.entitlements' 'Release documentation must explain the Language App Attest entitlement.'
Require-Pattern $releaseDocumentation 'GoogleService-Info\.plist' 'Release documentation must list Firebase plist inputs.'
Require-Pattern $releaseDocumentation 'MINIK_REMOVE_ADS_PRODUCT_IDENTIFIER' 'Release documentation must list the StoreKit product ID input.'
Require-Pattern $releaseDocumentation 'MINIK_INTERSTITIAL_AD_UNIT_IDENTIFIER' 'Release documentation must list the ad-unit input.'
Require-Pattern $releaseDocumentation 'privacy-policy-website-replacement\.md' 'Release documentation must route to the exact website privacy replacement.'
Require-Pattern $releaseDocumentation 'app-store-privacy-data-inventory\.md' 'Release documentation must route to the App Store privacy inventory.'
Require-Pattern $releaseDocumentation 'apple-release-checklist\.md' 'Release documentation must route to the Apple handoff checklist.'
Require-Pattern $privacyWebsiteReplacement 'child.s local or real profile name is not uploaded' 'Website privacy replacement must keep local names on device.'
Require-Pattern $privacyDataInventory 'MinikPlus[\s\S]*MinikPlusEnglish[\s\S]*MinikMathPlus[\s\S]*MinikMath\b[\s\S]*MinikPingPong' 'Privacy inventory must cover all five products.'
Require-Pattern $appleReleaseChecklist 'READY IN REPO[\s\S]*OWNER ACTION[\s\S]*LEGAL/POLICY DECISION[\s\S]*MAC/XCODE REQUIRED' 'Apple release checklist must classify repository, owner, legal/policy, and Mac work.'
Require-Pattern $project 'MINIK_REMOVE_ADS_PRODUCT_IDENTIFIER: remove_ads' 'Established Remove Ads product identifier is not configured.'
Require-Pattern $project 'MINIK_PRIVACY_POLICY_URL: https://miniklearn\.com/privacy[\s\S]*MINIK_TERMS_OF_USE_URL: https://www\.easycallandanswer\.com/terms\.html[\s\S]*MINIK_SUPPORT_URL: https://miniklearn\.com/contact' 'Established release destinations are not configured.'

Write-Output "RELEASE_APPICON_SETS_FOUND=$($iconSets.Count)"
Write-Output "RELEASE_ENTITLEMENT_FILES_FOUND=$($entitlementFiles.Count)"
Write-Output "RELEASE_PORTRAIT_ONLY_LANGUAGE_TARGETS=$($portraitOnlyTargets.Count)"
Write-Output "RELEASE_CANONICAL_BUNDLE_IDENTIFIERS=$($canonicalBundleConfigurations.Count)"
Write-Output "RELEASE_FORBIDDEN_BUNDLE_IDENTIFIER_ERRORS=$forbiddenBundleIdentifierErrors"
Write-Output "RELEASE_FIREBASE_PLIST_MAPPINGS=$($firebaseConfigurations.Count)"
Write-Output "RELEASE_FIREBASE_PLIST_MISMATCH_ERRORS=$firebasePlistMismatchErrors"
Write-Output "RELEASE_FIREBASE_CONFIGURE_CALLS=$firebaseConfigureCalls"
Write-Output 'RELEASE_REQUIRED_REASON_API_CATEGORIES=UserDefaults'
Write-Output "RELEASE_OTHER_REQUIRED_REASON_API_REFERENCES=$otherRequiredReasonAPIs"
Write-Output "RELEASE_CONFIGURATION_AUDIT_ERRORS=$($errors.Count)"
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output 'RELEASE_CONFIGURATION_AUDIT_OK'
