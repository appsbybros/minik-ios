$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$errors = [System.Collections.Generic.List[string]]::new()
$checks = @(
    @{ File = 'Sources/ProductConfiguration.swift'; Pattern = 'case \.minikPlusEnglish:[\s\S]*contentDomain: \.language[\s\S]*allowedLearnedLanguages: \[\.english\][\s\S]*fixedLearnedLanguage: \.english[\s\S]*isLearningLanguageSelectionAvailable: false'; Label = 'English Only configuration is a fixed-English Language product without a selector' },
    @{ File = 'Sources/ProductConfiguration.swift'; Pattern = 'if let fixedLearnedLanguage \{[\s\S]*return fixedLearnedLanguage'; Label = 'Restored learned-language state resolves through the fixed language' },
    @{ File = 'Sources/InterfaceLocale.swift'; Pattern = 'product == \.minikPlusEnglish[\s\S]*InterfaceLocaleID\.allCases\.filter \{ \$0 != \.hebrew \}'; Label = 'English Only excludes only Hebrew from interface locales' },
    @{ File = 'Sources/InterfaceLocale.swift'; Pattern = 'if let requested, allowed\.contains\(requested\) \{ return requested \}[\s\S]*return \.english'; Label = 'Disallowed interface state resolves safely to English' },
    @{ File = 'Sources/ParentAreaView.swift'; Pattern = 'if configuration\.isLearningLanguageSelectionAvailable \{[\s\S]*Picker\("Learned language"[\s\S]*\} else \{[\s\S]*LabeledContent\("Learned language", value: selectedLanguage\.hubTitle\)'; Label = 'Parent Area presents fixed English as read-only policy' },
    @{ File = 'Sources/MinikActivityHubView.swift'; Pattern = 'learnedLanguageRepository\.load\(for: configuration\)[\s\S]*Self\.defaultLearnedLanguage\(for: configuration\)'; Label = 'Hub restores learned language through product policy' },
    @{ File = 'Sources/MinikActivityHubView.swift'; Pattern = 'configuration\.fixedLearnedLanguage \?\?[\s\S]*configuration\.allowedLearnedLanguages'; Label = 'Hub defaults to the fixed learned language' },
    @{ File = 'Sources/MinikActivityHubView.swift'; Pattern = 'guard configuration\.allowsLearnedLanguage\(language\) else \{ return \}[\s\S]*configuration\.fixedLearnedLanguage \?\? language'; Label = 'Hub selection cannot bypass fixed English' },
    @{ File = 'Sources/MinikActivityHubView.swift'; Pattern = 'LanguageMenuView\([\s\S]*learnedLanguage: selectedLanguage[\s\S]*onSelect: launchLanguageActivity[\s\S]*private func launchLanguageActivity\(_ activity: LanguageActivityKind\)[\s\S]*route = \.language\(activity, selectedLanguage'; Label = 'All child Language routes use the policy-resolved learned language' },
    @{ File = 'Sources/LanguageShellViews.swift'; Pattern = 'for section in ActivityCatalog\.languageSections\(for: configuration\)'; Label = 'The Language menu lists only the policy-resolved activities' },
    @{ File = 'Sources/LanguageShellViews.swift'; Pattern = 'func menuArtworkName\(for activity: LanguageActivityKind\)[\s\S]*let english = learnedLanguage == \.english'; Label = 'Activity artwork follows the policy-resolved language' },
    @{ File = 'Sources/InterfaceSpeech.swift'; Pattern = 'func speak\(_ text: String, interfaceLocale: InterfaceLocaleID\)[\s\S]*interfaceLocale\.rawValue'; Label = 'Interface speech follows the independently selected allowed interface locale' },
    @{ File = 'Sources/LearningSpeech.swift'; Pattern = 'LearningSpeechVoiceLocale\.identifier\(for: item\.language\)'; Label = 'Learned speech follows typed learned-language metadata' },
    @{ File = 'Tests/ProductConfigurationTests/LanguageProductionParityTests.swift'; Pattern = 'testEnglishOnlyLocksTheSameThirteenRoutesToEnglishPolicy'; Label = 'Deterministic 13-route and product-isolation coverage exists' },
    @{ File = 'Tests/ProductConfigurationTests/LanguageProductionParityTests.swift'; Pattern = 'testEnglishOnlyProductionArtworkNeverSelectsHebrewVariants'; Label = 'Deterministic English artwork guard exists' },
    @{ File = 'Tests/ProductConfigurationTests/LanguageProductionParityTests.swift'; Pattern = 'testEnglishOnlySpeechBearingProductionSessionsUseEnglishLearnedSpeech'; Label = 'Deterministic learned-speech metadata coverage exists' },
    @{ File = 'Tests/ProductConfigurationTests/ProductConfigurationTests.swift'; Pattern = 'testMinikPlusEnglishAllowsOnlyEnglish[\s\S]*allowedLearnedLanguages, \[\.english\][\s\S]*fixedLearnedLanguage, \.english'; Label = 'Fixed-English configuration coverage exists' },
    @{ File = 'Tests/ProductConfigurationTests/ParentAreaPolicyTests.swift'; Pattern = 'testEnglishOnlyAlwaysResolvesLearnedLanguageToEnglish'; Label = 'Persisted Hebrew learned state regression coverage exists' },
    @{ File = 'Tests/ProductConfigurationTests/InterfaceLocaleTests.swift'; Pattern = 'testEnglishOnlyProductExcludesHebrewInterfaceLocale'; Label = 'Interface-locale exclusion coverage exists' }
)

foreach ($check in $checks) {
    $path = Join-Path $repoRoot $check.File
    $source = Get-Content -LiteralPath $path -Raw -Encoding utf8
    if ($source -notmatch $check.Pattern) {
        $errors.Add("Missing $($check.Label) [$($check.File)]")
    }
}

$expectedActivities = @(
    'learn', 'letterPairs', 'firstLetterChoices', 'firstLetterPictures',
    'mixed', 'wordBuild', 'imageToWord', 'wordToImage', 'wordCards',
    'soccer', 'tower', 'wordMemory', 'ticTacToe'
)
$record = @(Import-Csv -LiteralPath (Join-Path $repoRoot 'docs/language-production-parity-lock.tsv') -Delimiter "`t")
if ($record.Count -ne 13 -or
    (($record.activity_id -join '|') -ne ($expectedActivities -join '|'))) {
    $errors.Add('English Only no longer inherits the exact ordered 13-activity production record.')
}

$project = Get-Content -LiteralPath (Join-Path $repoRoot 'project.yml') -Raw -Encoding utf8
$targetMatch = [regex]::Match($project, '(?ms)^  MinikPlusEnglish:\r?\n(?<body>.*?)(?=^  MinikMathPlus:)')
if (-not $targetMatch.Success) {
    $errors.Add('MinikPlusEnglish target block is missing from project.yml.')
} else {
    $body = $targetMatch.Groups['body'].Value
    foreach ($required in @(
        'Resources/LanguageImages.xcassets',
        'Resources/Vocabulary/words-normalized.xml',
        'Resources/Localization/EnglishOnly/Localizable.xcstrings',
        'CFBundleLocalizations: [en, am, ar, de, es, fr, nl, pt-BR, pt-PT, ru]',
        'MINIK_PLUS_ENGLISH'
    )) {
        if ($body -notmatch [regex]::Escape($required)) {
            $errors.Add("MinikPlusEnglish target is missing required policy entry: $required")
        }
    }
    foreach ($forbidden in @('Resources/MathObjects.xcassets', 'Resources/PingPongAssets.xcassets', 'Resources/Localization/All/Localizable.xcstrings')) {
        if ($body -match [regex]::Escape($forbidden)) {
            $errors.Add("MinikPlusEnglish target leaks another product resource: $forbidden")
        }
    }
}

$hub = Get-Content -LiteralPath (Join-Path $repoRoot 'Sources/MinikActivityHubView.swift') -Raw -Encoding utf8
if ($hub -match 'languageSelectorSection|shouldShowLanguageSelector') {
    $errors.Add('A learned-language selector leaked back onto child-facing Home.')
}

Write-Output "ENGLISH_ONLY_POLICY_CONTRACTS_AUDITED=$($checks.Count + 4)"
Write-Output "ENGLISH_ONLY_POLICY_ERRORS=$($errors.Count)"
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Output 'ENGLISH_ONLY_PRODUCTION_POLICY_OK'
