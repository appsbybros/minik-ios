[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$errors = [System.Collections.Generic.List[string]]::new()

function Require-Pattern([string]$Path, [string]$Pattern, [string]$Message) {
    $source = [IO.File]::ReadAllText((Join-Path $root $Path), [Text.Encoding]::UTF8)
    if ($source -notmatch $Pattern) { $errors.Add("${Path}: $Message") }
}

Require-Pattern 'project.yml' 'AppStoreCommerceKit:[\s\S]*path: Packages/AppStoreCommerceKit' 'local commerce package is not declared'
Require-Pattern 'project.yml' 'MinikRemoveAdsProductIdentifier: \$\(MINIK_REMOVE_ADS_PRODUCT_IDENTIFIER\)' 'injectable product-ID Info hook missing'
Require-Pattern 'Sources/MinikCommerce.swift' 'supportedProductKinds: \[\.nonConsumable\]' 'Remove Ads must be a non-consumable'
Require-Pattern 'Sources/MinikCommerce.swift' 'StoreKitCommerceStore\(' 'production StoreKit adapter is not composed'
Require-Pattern 'Sources/MinikCommerce.swift' 'transactionUpdates\(\)' 'transaction update listener missing'
Require-Pattern 'Sources/MinikCommerce.swift' 'refreshEntitlements\(\)' 'entitlement reconciliation missing'
Require-Pattern 'Sources/MinikCommerce.swift' 'restorePurchases\(\)' 'explicit restore missing'
Require-Pattern 'Sources/RootView.swift' 'commerceController\.start\(\)' 'commerce does not start with the app root'
Require-Pattern 'Sources/RootView.swift' 'newPhase == \.active[\s\S]*commerceController\.refreshEntitlements\(\)' 'foreground entitlement refresh missing'
Require-Pattern 'Sources/ParentAreaView.swift' 'ParentalGateView[\s\S]*purchaseRemoveAds\(\)[\s\S]*restorePurchases\(\)' 'gated Parent purchase/restore flow missing'
Require-Pattern 'Tests/ProductConfigurationTests/MinikCommerceIntegrationTests.swift' 'testTransactionUpdateAndRestoreReconcileAuthoritativeState' 'transaction/restore regression missing'

$project = [IO.File]::ReadAllText((Join-Path $root 'project.yml'), [Text.Encoding]::UTF8)
foreach ($target in @('MinikPlus', 'MinikPlusEnglish', 'MinikMathPlus', 'MinikMath', 'MinikPingPong', 'ProductConfigurationTests')) {
    $match = [regex]::Match($project, "(?ms)^  ${target}:(?<body>[\s\S]*?)(?=^  [A-Za-z][A-Za-z0-9]+:|\z)")
    if (-not $match.Success -or $match.Groups['body'].Value -notmatch 'package: AppStoreCommerceKit') {
        $errors.Add("$target does not link AppStoreCommerceKit despite compiling the shared Sources layer.")
    }
}

if ($project -match '(?i)(fixture|test)\.[A-Za-z0-9.-]*remove.?ads') {
    $errors.Add('A fixture/test Remove Ads identifier leaked into production project configuration.')
}

$errors | ForEach-Object { "MINIK_COMMERCE_ERROR=$_" }
"MINIK_COMMERCE_ERRORS=$($errors.Count)"
if ($errors.Count -gt 0) { exit 1 }
