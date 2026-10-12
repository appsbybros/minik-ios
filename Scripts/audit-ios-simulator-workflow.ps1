[CmdletBinding()]
param(
    [string]$WorkflowPath
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($WorkflowPath)) {
    $WorkflowPath = Join-Path $PSScriptRoot "..\.github\workflows\ios-simulator.yml"
}
$workflow = Get-Content -Raw -Encoding utf8 $WorkflowPath
$workflow = $workflow.Replace("`r`n", "`n").Replace("`r", "`n")
$errors = [System.Collections.Generic.List[string]]::new()
$workflowDirectory = Split-Path -Parent $WorkflowPath

function Require-Match([string]$Pattern, [string]$Message) {
    if ($workflow -notmatch $Pattern) {
        $errors.Add($Message)
    }
}

function Reject-Match([string]$Pattern, [string]$Message) {
    if ($workflow -match $Pattern) {
        $errors.Add($Message)
    }
}

Require-Match '(?m)^on:$' "Missing top-level on block."
Require-Match '(?m)^  workflow_dispatch:$' "workflow_dispatch is required."
Reject-Match 'inputs\.product' "The Simulator gate must always build every product."
Require-Match '(?m)^      run_tests:$' "Running ProductConfigurationTests must be an explicit choice."
Require-Match 'ARCHS=arm64' "Simulator builds must target only the Apple-silicon runner architecture."
Require-Match 'DERIVED_DATA="build/DerivedData/Shared"' "All products must share one DerivedData so packages build once."

Require-Match '(?m)^    runs-on: macos-latest$' "The workflow must use macos-latest."
Require-Match '(?m)^    timeout-minutes: 90$' "The workflow must have a 90-minute timeout."
Require-Match '(?m)^      - name: Build and package all Simulator apps$' "The dedicated gate must build and package all products."
Require-Match 'SCHEMES=\(MinikPlus MinikPlusEnglish MinikMathPlus MinikPingPong MinikRetroPingPong\)' "The five-product scheme list is incomplete."
Reject-Match 'SELECTED_PRODUCT|SCHEMES=\("\$SELECTED_PRODUCT"\)' "The complete gate must not contain a one-product path."
Require-Match 'Debug-iphonesimulator/\$SCHEME\.app' "The exact Simulator app path is missing."
Require-Match 'ditto -c -k --sequesterRsrc --keepParent' "The app bundle must be packaged with ditto."
Require-Match 'CODE_SIGN_IDENTITY=""' "Unsigned Simulator building must clear the signing identity."
Require-Match 'CODE_SIGNING_REQUIRED=NO' "Unsigned Simulator building must disable required signing."
Require-Match 'CODE_SIGNING_ALLOWED=NO' "Unsigned Simulator building must disable signing."
Require-Match 'ONLY_ACTIVE_ARCH=NO' "Universal Simulator architecture building is not explicit."
Require-Match 'failed_schemes=\(\)' "The workflow must collect product build failures."
Require-Match 'failed_packages=\(\)' "The workflow must collect product packaging failures separately."
Require-Match 'build_status=\$\{PIPESTATUS\[0\]\}' "The workflow must capture each xcodebuild exit status."
Require-Match 'Build failures:' "The workflow must report aggregate compile failures."
Require-Match 'Packaging failures:' "The workflow must report aggregate packaging failures."
Require-Match 'echo "compiles_clean=\$compiles_clean"' "The workflow must publish aggregate compile readiness."
Require-Match 'echo "packages_clean=\$packages_clean"' "The workflow must publish aggregate packaging readiness."
Require-Match 'ZIP_PATH="build/artifacts/\$SCHEME-simulator\.zip"' "Each successful product must use an explicit ZIP path."
Require-Match 'if \[ ! -s "\$ZIP_PATH" \]; then' "A product must not be marked ready unless its ZIP exists and is nonempty."
Require-Match '(?s)name: Upload Simulator build logs.*?if: \$\{\{ !cancelled\(\) \}\}.*?name: Simulator-build-logs.*?path: build/logs/\*\.log.*?retention-days: 3' "Build logs must upload after partial or complete build results with three-day retention."

Require-Match '(?m)^      - name: Select and boot modern iPhone and iPad Simulators$' "The workflow must prepare a modern iPhone and an iPad Simulator."
Require-Match 'name\.startswith\("iPad"\)' "Simulator selection must include an iPad."
Require-Match 'DEVICE_ROLES=\(iPhone iPad\)' "Every product must be smoke-tested on iPhone and iPad."
Require-Match '-MinikOfflineSmoke YES' "Smoke launches must keep Modern Ping Pong offline."
Require-Match 'IPAD_READY' "The final gate must require a booted iPad Simulator."
Require-Match 'simctl list devices available -j' "The workflow must inspect available Simulator devices."
Require-Match 'model_number = int\(model_match\.group\(1\)\)' "Simulator selection must prefer a modern iPhone model."
Require-Match 'xcrun simctl boot "\$SIMULATOR_UDID"' "The selected Simulator must be booted."
Require-Match 'xcrun simctl bootstatus "\$SIMULATOR_UDID" -b' "The workflow must wait for Simulator boot completion."
Require-Match 'echo "udid=\$SIMULATOR_UDID"' "The selected Simulator UDID must be shared with later steps."

Require-Match '(?m)^        if: \$\{\{ inputs\.run_tests && steps\.product_builds\.outputs\.compiles_clean == ''true'' && steps\.prepare_simulator\.outputs\.simulator_ready == ''true'' \}\}$' "ProductConfigurationTests must run only after all four builds compile cleanly and the Simulator boots."
Require-Match '(?m)^        continue-on-error: true$' "The single XCTest result must be aggregated by the final gate verdict."
Require-Match '(?m)^\s+xcodebuild test \\$' "The workflow must run XCTest."
Require-Match '(?m)^\s+-only-testing:ProductConfigurationTests \\$' "The workflow must select ProductConfigurationTests."
Require-Match '-derivedDataPath build/DerivedData/Shared' "Tests must reuse the shared DerivedData."

Require-Match '(?m)^      - name: Install, launch, capture, and terminate all Simulator apps$' "The four-product runtime smoke step is missing."
Require-Match '(?m)^        if: \$\{\{ always\(\) \}\}$' "Runtime evidence collection must continue after earlier failures."
Require-Match '/usr/libexec/PlistBuddy -c ''Print :CFBundleIdentifier'' "\$APP_PATH/Info\.plist"' "Bundle identifiers must be read from each built app Info.plist."
Require-Match 'xcrun simctl install "\$SIMULATOR_UDID" "\$APP_PATH"' "Each ready app must be installed with simctl."
Require-Match 'xcrun simctl launch "\$SIMULATOR_UDID" "\$BUNDLE_IDENTIFIER"' "Each ready app must launch using its discovered bundle identifier."
Require-Match 'sleep 5' "The workflow must allow a brief stable-render interval."
Require-Match 'xcrun simctl io "\$SIMULATOR_UDID" screenshot "\$SCREENSHOT_PATH"' "Each ready app must capture a Simulator screenshot."
Require-Match 'xcrun simctl spawn "\$SIMULATOR_UDID" log show' "Each ready app must collect console diagnostics."
Require-Match 'xcrun simctl terminate "\$SIMULATOR_UDID" "\$BUNDLE_IDENTIFIER"' "Each launched app must be terminated before continuing."
Require-Match 'smoke-summary\.json' "The workflow must create a machine-readable smoke summary."
Require-Match 'all_required_products_passed' "The smoke summary must state aggregate required-product success."
Require-Match 'Library/Logs/DiagnosticReports' "The workflow must collect generated crash reports."
Require-Match 'Library/Logs/CrashReporter' "The workflow must inspect Simulator crash reports."
Require-Match '(?s)name: Upload Simulator smoke validation.*?name: Simulator-smoke-validation.*?path: build/smoke.*?if-no-files-found: error.*?retention-days: 3' "The complete smoke evidence artifact must always use three-day retention."

$productOutputs = [ordered]@{
    MinikPlus = "minikplus_ready"
    MinikPlusEnglish = "minikplusenglish_ready"
    MinikMathPlus = "minikmathplus_ready"
    MinikPingPong = "minikpingpong_ready"
    MinikRetroPingPong = "minikretropingpong_ready"
}
$productBuildOutputs = [ordered]@{
    MinikPlus = "minikplus_built"
    MinikPlusEnglish = "minikplusenglish_built"
    MinikMathPlus = "minikmathplus_built"
    MinikPingPong = "minikpingpong_built"
    MinikRetroPingPong = "minikretropingpong_built"
}
$productBuildVariables = [ordered]@{
    MinikPlus = "minik_plus_built"
    MinikPlusEnglish = "minik_plus_english_built"
    MinikMathPlus = "minik_math_plus_built"
    MinikPingPong = "minik_ping_pong_built"
    MinikRetroPingPong = "minik_retro_ping_pong_built"
}
$productVariables = [ordered]@{
    MinikPlus = "minik_plus_ready"
    MinikPlusEnglish = "minik_plus_english_ready"
    MinikMathPlus = "minik_math_plus_ready"
    MinikPingPong = "minik_ping_pong_ready"
    MinikRetroPingPong = "minik_retro_ping_pong_ready"
}

foreach ($product in $productOutputs.Keys) {
    $outputName = $productOutputs[$product]
    $variableName = $productVariables[$product]
    $buildOutputName = $productBuildOutputs[$product]
    $buildVariableName = $productBuildVariables[$product]
    $successAssignment = "$product) $variableName=true ;;"
    $buildAssignment = "$product) $buildVariableName=true ;;"
    $outputEmission = 'echo "{0}=${1}"' -f $outputName, $variableName
    $buildOutputEmission = 'echo "{0}=${1}"' -f $buildOutputName, $buildVariableName
    Require-Match "build/artifacts/$product-simulator\.zip" "Missing ZIP path for $product."
    Require-Match ([regex]::Escape($successAssignment)) "Missing explicit successful-package state for $product."
    Require-Match ([regex]::Escape($buildAssignment)) "Missing explicit successful-build state for $product."
    Require-Match ([regex]::Escape($outputEmission)) "Missing GitHub Actions output for $product."
    Require-Match ([regex]::Escape($buildOutputEmission)) "Missing GitHub Actions successful-build output for $product."
    Require-Match "(?s)name: Upload $product Simulator artifact.*?if: \$\{\{ !cancelled\(\) && steps\.product_builds\.outputs\.$outputName == 'true' \}\}.*?name: $product-simulator.*?build/artifacts/$product-simulator\.zip.*?if-no-files-found: error.*?retention-days: 3" "The $product artifact must upload only from its explicit successful-package output with three-day retention."
    $smokeReadinessPattern = '(?s)case "\$SCHEME" in.*?' + [regex]::Escape($product) + '\) BUILD_SUCCEEDED="\$[A-Z_]+" ;;'
    Require-Match $smokeReadinessPattern "The smoke loop must map explicit build readiness for $product."
    Require-Match 'build/smoke/screenshots/\$SCHEME-\$DEVICE_ROLE\.png' "The smoke loop must create a screenshot path for $product."
}

$schemeListCount = [regex]::Matches($workflow, 'SCHEMES=\(MinikPlus MinikPlusEnglish MinikMathPlus MinikPingPong MinikRetroPingPong\)').Count
if ($schemeListCount -ne 2) {
    $errors.Add("The exact all-product list must drive both build and smoke loops; found $schemeListCount copies.")
}

$zipValidationIndex = $workflow.IndexOf('if [ ! -s "$ZIP_PATH" ]; then')
$successStateIndex = $workflow.IndexOf('case "$SCHEME" in', $zipValidationIndex + 1)
$buildCleanIndex = $workflow.IndexOf('compiles_clean=true', $successStateIndex + 1)
$outputEmissionIndex = $workflow.IndexOf('echo "minikplus_ready=$minik_plus_ready"')
if ($zipValidationIndex -lt 0 -or
    $successStateIndex -le $zipValidationIndex -or
    $buildCleanIndex -le $successStateIndex -or
    $outputEmissionIndex -le $buildCleanIndex) {
    $errors.Add("Per-product success outputs must be set only after ZIP validation and emitted with aggregate build readiness.")
}

$retentionCount = [regex]::Matches($workflow, '(?m)^\s+retention-days: 3$').Count
if ($retentionCount -ne 8) {
    $errors.Add("Expected eight short-retention upload steps; found $retentionCount.")
}

$testCommandCount = [regex]::Matches($workflow, '(?m)^\s+xcodebuild test \\$').Count
if ($testCommandCount -ne 1) {
    $errors.Add("ProductConfigurationTests must appear exactly once; found $testCommandCount test commands.")
}

$macOSJobCount = [regex]::Matches($workflow, '(?m)^    runs-on: macos-latest$').Count
if ($macOSJobCount -ne 1) {
    $errors.Add("The preferred workflow must use exactly one macOS job; found $macOSJobCount.")
}

$checkoutCount = [regex]::Matches($workflow, 'uses: actions/checkout@').Count
if ($checkoutCount -ne 1) {
    $errors.Add("The complete gate must use exactly one checkout; found $checkoutCount.")
}

$buildStepIndex = $workflow.IndexOf("- name: Build and package all Simulator apps")
$simulatorStepIndex = $workflow.IndexOf("- name: Select and boot modern iPhone and iPad Simulators")
$testStepIndex = $workflow.IndexOf("- name: Run ProductConfigurationTests once")
$smokeStepIndex = $workflow.IndexOf("- name: Install, launch, capture, and terminate all Simulator apps")
$smokeUploadIndex = $workflow.IndexOf("- name: Upload Simulator smoke validation")
$finalStepIndex = $workflow.IndexOf("- name: Evaluate complete Simulator gate")
if ($buildStepIndex -lt 0 -or
    $simulatorStepIndex -le $buildStepIndex -or
    $testStepIndex -le $simulatorStepIndex -or
    $smokeStepIndex -le $testStepIndex -or
    $smokeUploadIndex -le $smokeStepIndex -or
    $finalStepIndex -le $smokeUploadIndex) {
    $errors.Add("Builds, Simulator boot, one XCTest pass, four smoke attempts, evidence upload, and final verdict must remain in that order.")
}

Require-Match '(?m)^      - name: Evaluate complete Simulator gate$' "The workflow must end with an aggregate gate verdict."
Require-Match 'failures=\(\)' "The final gate must collect all required failure classes."
Require-Match 'COMPILES_CLEAN: \$\{\{ steps\.product_builds\.outputs\.compiles_clean \}\}' "The final gate must evaluate aggregate compilation."
Require-Match 'PACKAGES_CLEAN: \$\{\{ steps\.product_builds\.outputs\.packages_clean \}\}' "The final gate must evaluate aggregate packaging."
Require-Match 'TEST_OUTCOME: \$\{\{ steps\.product_tests\.outcome \}\}' "The final gate must evaluate the XCTest outcome."
Require-Match 'SMOKE_CLEAN: \$\{\{ steps\.simulator_smoke\.outputs\.smoke_clean \}\}' "The final gate must evaluate all runtime checks."
Require-Match 'if \(\( \$\{#failures\[@\]\} > 0 \)\); then' "The final gate must fail after aggregating required failures."

Reject-Match '\|\|\s*true' "Hidden failure handling is forbidden."
Reject-Match 'actions/cache@' "No cache action is allowed in this workflow."
Reject-Match '(?m)^\s+build/DerivedData\s*$' "DerivedData must not be uploaded."
Reject-Match '(?s)name: Upload (?:MinikPlus|MinikPlusEnglish|MinikMathPlus|MinikPingPong|MinikRetroPingPong) Simulator artifact.*?steps\.product_builds\.outcome == ''success''' "Product artifact uploads must not depend on aggregate build-step success."
Reject-Match '(?i)codemagic|appetize|browserstack|sauce\s*labs|maestro' "The GitHub-hosted gate must not invoke an external testing service or optional Maestro setup."
Reject-Match '(?i)AppStoreCommerceKit|grace[-_ ]?period' "The hosted AppStoreCommerceKit grace-period workflow/test is forbidden here."
Reject-Match '\$\{\{\s*secrets\.' "The Simulator gate must not require repository secrets."
Reject-Match '(?i)PROVISIONING_PROFILE|CODE_SIGNING_ALLOWED=YES|DEVELOPMENT_TEAM=' "The Simulator gate must not require signing configuration."
Reject-Match '(?i)FirebaseApp\.configure|GoogleService-Info|AdMob|GADApplicationIdentifier' "The Simulator gate must not inject production Firebase or ad configuration."

$workflowFiles = Get-ChildItem -File $workflowDirectory |
    Where-Object { $_.Extension -in @(".yml", ".yaml") } |
    Sort-Object Name

if ($workflowFiles.Count -eq 0) {
    $errors.Add("No .yml or .yaml workflow files were found.")
}

foreach ($workflowFile in $workflowFiles) {
    $lines = @(Get-Content -Encoding utf8 $workflowFile.FullName)
    $onLines = @(
        for ($index = 0; $index -lt $lines.Count; $index += 1) {
            if ($lines[$index] -match '^on:\s*(?:#.*)?$') {
                $index
            }
        }
    )

    if ($onLines.Count -ne 1) {
        $errors.Add("$($workflowFile.Name) must contain exactly one top-level on: mapping; found $($onLines.Count).")
        continue
    }

    $triggers = [System.Collections.Generic.List[string]]::new()
    for ($index = $onLines[0] + 1; $index -lt $lines.Count; $index += 1) {
        $line = $lines[$index]
        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\s*#') {
            continue
        }
        if ($line -match '^\S') {
            break
        }
        if ($line -match '^ {2}([^\s:#][^:]*?)\s*:(?:\s|$)') {
            $trigger = $Matches[1].Trim().Trim('"').Trim("'")
            $triggers.Add($trigger)
        } elseif ($line -match '^ {2}\S') {
            $errors.Add("$($workflowFile.Name) contains an unparseable level-2 entry in its on: block: $line")
        }
    }

    if ($triggers.Count -ne 1 -or $triggers[0] -ne "workflow_dispatch") {
        $triggerSummary = if ($triggers.Count -eq 0) { "<none>" } else { $triggers -join ", " }
        $errors.Add("$($workflowFile.Name) has disallowed top-level workflow event(s): $triggerSummary. Only workflow_dispatch is permitted.")
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output "IOS_SIMULATOR_WORKFLOW_ERRORS=0"
Write-Output "IOS_SIMULATOR_WORKFLOW_TRIGGER=workflow_dispatch"
Write-Output "IOS_SIMULATOR_WORKFLOW_PRODUCTS=5"
Write-Output "IOS_SIMULATOR_WORKFLOW_TEST_COMMANDS=$testCommandCount"
Write-Output "IOS_SIMULATOR_WORKFLOW_RETENTION_UPLOADS=$retentionCount"
Write-Output "IOS_SIMULATOR_WORKFLOW_SMOKE_SUMMARY=smoke-summary.json"
Write-Output "IOS_SIMULATOR_WORKFLOW_LINE_ENDINGS=NORMALIZED_LF_CRLF"
Write-Output "WORKFLOW_DIRECTORY_AUTOMATIC_TRIGGER_ERRORS=0"
Write-Output "WORKFLOW_DIRECTORY_FILES_AUDITED=$($workflowFiles.Count)"
