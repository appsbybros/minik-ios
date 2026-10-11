$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$checks = @(
    @{ File = 'Sources/SoccerIntroduction.swift'; Pattern = 'maximumPresentationCount = 3'; Label = 'Introduction is limited to first three presentations' },
    @{ File = 'Sources/MinikActivityHubView.swift'; Pattern = 'case \.soccer:[\s\S]*LanguageSoccerView\([\s\S]*parentSoccerLevel: languageLevelSettings\.soccerLevel'; Label = 'Production route consumes Parent Soccer level' },
    @{ File = 'Sources/LanguageSoccerView.swift'; Pattern = 'interfaceLocaleID\.text\("Drag the letters in the correct order to spell the word shown\."\)[\s\S]*interfaceLocaleID\.text\("Try to score a goal against Minik with each letter\."\)[\s\S]*interfaceLocaleID\.text\("Correct letter \+ goal = 1 point for you!"\)[\s\S]*interfaceLocaleID\.text\("Wrong letter \+ no goal = 1 point for Minik!"\)'; Label = 'Language Soccer introduction is the four short drag lines (QA ISSUE-008)' },
    @{ File = 'Sources/LanguageSoccerView.swift'; Pattern = '@State private var showsMoreInformation = false[\s\S]*interfaceLocaleID\.text\("More Information"\)[\s\S]*if showsMoreInformation \{[\s\S]*soccerMoreInformationLines'; Label = 'Further Soccer rules sit under More Information, collapsed by default' },
    @{ File = 'Sources/SoccerView.swift'; Pattern = 'String\(localized: "Tap letters in the correct order'; Label = 'Shared and Math Soccer retain the pre-reconstruction tap introduction' },
    @{ File = 'Sources/LanguageSoccerView.swift'; Pattern = 'DragGesture\(minimumDistance: 6'; Label = 'Primary interaction is drag' },
    @{ File = 'Sources/LanguageSoccerView.swift'; Pattern = 'shouldLaunchDuringDrag[\s\S]*shouldLaunchOnRelease'; Label = 'Crossing and release launch paths exist' },
    @{ File = 'Sources/LanguageSoccerView.swift'; Pattern = 'LanguageSoccerShotGeometry\([\s\S]*practice\.resolveShot\(outcome: resolution\.outcome\)'; Label = 'Physical geometry determines score outcome' },
    @{ File = 'Sources/LanguageSoccerShotPhysics.swift'; Pattern = 'case idle[\s\S]*case dragging[\s\S]*case launched[\s\S]*case inFlight[\s\S]*case rebounding[\s\S]*case finalized'; Label = 'Typed shot lifecycle is complete' },
    @{ File = 'Sources/LanguageSoccerShotPhysics.swift'; Pattern = 'activeID == shotID'; Label = 'Stale callbacks are identity-gated' },
    @{ File = 'Sources/LanguageSoccerShotPhysics.swift'; Pattern = '\.keeper[\s\S]*\.leftPost[\s\S]*\.rightPost[\s\S]*\.crossbar'; Label = 'Keeper, posts, and crossbar are physical collisions' },
    @{ File = 'Sources/LanguageSoccerShotPhysics.swift'; Pattern = 'case \.a: return attemptIndex >= 3[\s\S]*case \.b: return attemptIndex >= 2[\s\S]*case \.c: return true'; Label = 'Android A/B/C first-keeper movement is encoded' },
    @{ File = 'Sources/LanguageSoccerShotPhysics.swift'; Pattern = '\(3\.0, 2\.0, 1\.0\)[\s\S]*\(1\.1, 0\.5, 0\.6\)[\s\S]*\(0\.8, 0\.4, 0\.4\)'; Label = 'Android A/B/C sweep timing is encoded' },
    @{ File = 'Sources/LanguageSoccerView.swift'; Pattern = 'MinikVisualAsset\.soccerField[\s\S]*MinikVisualAsset\.soccerGoal[\s\S]*MinikVisualAsset\.soccerGoalie'; Label = 'Original field, goal, and keeper are composed' },
    @{ File = 'Sources/LanguageSoccerView.swift'; Pattern = 'MinikVisualAsset\.soccerBall'; Label = 'Launched letter uses original football art' },
    @{ File = 'Sources/LanguageSoccerView.swift'; Pattern = 'func introductionBackdrop[\s\S]*MinikSkyBackground\(\)'; Label = 'Introduction uses the sky of the new design' },
    @{ File = 'Sources/LanguageSoccerView.swift'; Pattern = 'frame\(minWidth: 56, minHeight: 56\)'; Label = 'Letter controls retain accessible hit targets' },
    @{ File = 'Sources/LanguageSoccerView.swift'; Pattern = 'accessibilityAction[\s\S]*beginAccessibleShot'; Label = 'Non-primary accessibility launch fallback exists' },
    @{ File = 'Sources/LanguageSoccerView.swift'; Pattern = 'attemptTracker\.makeAttempt\([\s\S]*activityFamily: \.soccer'; Label = 'Specialized semantic token attempts are emitted' },
    @{ File = 'Sources/LanguageSoccerView.swift'; Pattern = 'selectedOrderedTokenSpeechCue[\s\S]*currentSpeechCue'; Label = 'Letter and target speech are preserved' },
    @{ File = 'Sources/LanguageSoccerView.swift'; Pattern = 'speakCompletedRoundResult[\s\S]*enqueueInterfaceSpeech'; Label = 'Completed word and interface result speech are queued once' },
    @{ File = 'Sources/LanguageSoccerSoundPlayer.swift'; Pattern = 'func playKick\(\)[\s\S]*play\(named: "minik_kick"\)'; Label = 'Launch and rebound use the Android kick sound' },
    @{ File = 'Sources/LanguageSoccerView.swift'; Pattern = 'educationalWasCorrect == false, resolution\.outcome == \.goal[\s\S]*playWrongLetterGoal'; Label = 'Android wrong-letter goal uses its dedicated swoosh' },
    @{ File = 'Sources/LanguageSoccerView.swift'; Pattern = 'onChange\(of: scenePhase\)[\s\S]*suspendActiveShot[\s\S]*onDisappear\(perform: stopAudioAndMotion\)[\s\S]*shotTask\?\.cancel\(\)'; Label = 'Background and exit invalidate motion and audio' },
    @{ File = 'Sources/LanguageSoccerPracticeSession.swift'; Pattern = 'LanguageSoccerPoolBoundary[\s\S]*lastAdvanceBoundary'; Label = 'Pool exhaustion is exposed as typed local evidence' },
    @{ File = 'Tests/ProductConfigurationTests/LanguageSoccerContentProviderTests.swift'; Pattern = 'testOrderedTokenScoreMatrixMatchesAndroid'; Label = 'Android score matrix is tested' },
    @{ File = 'Tests/ProductConfigurationTests/LanguageSoccerContentProviderTests.swift'; Pattern = 'testCorrectNextTokenAdvancesConsumesAndBuildsEvenWhenShotIsSaved'; Label = 'Correct token consumption ignores shot result' },
    @{ File = 'Tests/ProductConfigurationTests/LanguageSoccerContentProviderTests.swift'; Pattern = 'testWrongTokenDoesNotAdvanceOrConsumeAndRemainsAvailableAfterGoal'; Label = 'Wrong token retry ignores shot result' },
    @{ File = 'Tests/ProductConfigurationTests/LanguageSoccerContentProviderTests.swift'; Pattern = 'testDuplicateLettersUseDistinctIDsAndEquivalentInstanceCanSatisfyNextToken'; Label = 'Duplicate physical letters are tested' },
    @{ File = 'Tests/ProductConfigurationTests/LanguageSoccerShotPhysicsTests.swift'; Pattern = 'testLifecycleRejectsStaleAndDuplicateCallbacks'; Label = 'Exact-once lifecycle is tested' },
    @{ File = 'Tests/ProductConfigurationTests/LanguageSoccerShotPhysicsTests.swift'; Pattern = 'testLaunchCapturesTheSelectedPhysicalBallID[\s\S]*testMissFinalizesExactlyOnce[\s\S]*testKeeperAndFrameReboundsCannotFinalizeTwice'; Label = 'Physical identity and all finalization paths are tested' },
    @{ File = 'Tests/ProductConfigurationTests/LanguageSoccerShotPhysicsTests.swift'; Pattern = 'testDragDirectionControlsGoalAndMiss'; Label = 'Drag direction physical outcomes are tested' },
    @{ File = 'Tests/ProductConfigurationTests/LanguageSoccerShotPhysicsTests.swift'; Pattern = 'testCrossbarCollisionIsRepresented'; Label = 'Crossbar collision is tested' },
    @{ File = 'Tests/ProductConfigurationTests/LanguageSoccerShotPhysicsTests.swift'; Pattern = 'testLevelAFirstTwoKeepersAreStationaryThenThirdMoves[\s\S]*testLevelBFirstKeeperIsStationaryThenMovementPersists[\s\S]*testLevelCStartsMovingImmediately'; Label = 'All first-keeper behaviors are tested' },
    @{ File = 'Tests/ProductConfigurationTests/LanguageSoccerShotPhysicsTests.swift'; Pattern = 'testProductionConfigurationConsumesThePersistedParentSoccerLevel'; Label = 'Typed production configuration consumes Parent Soccer level' },
    @{ File = 'Tests/ProductConfigurationTests/SoccerSessionTests.swift'; Pattern = 'testOrderedKickPreparationDoesNotChangeAnswerChoiceFlow'; Label = 'Shared Math answer-choice Soccer remains covered' }
)

$errors = [Collections.Generic.List[string]]::new()
foreach ($check in $checks) {
    $source = Get-Content -LiteralPath (Join-Path $repoRoot $check.File) -Raw -Encoding utf8
    if ($source -notmatch $check.Pattern) {
        $errors.Add("Missing Soccer release contract: $($check.Label) [$($check.File)]")
    }
}

$view = Get-Content -LiteralPath (Join-Path $repoRoot 'Sources/LanguageSoccerView.swift') -Raw -Encoding utf8
if ($view -match 'simulatedOutcome|resolveShot\(outcome:\s*[^\r\n]*random') {
    $errors.Add('Production Language Soccer still contains a simulated/random shot outcome.')
}
$scrollCount = ([regex]::Matches($view, 'ScrollView')).Count
if ($scrollCount -gt 1 -or ($scrollCount -eq 1 -and $view -notmatch 'private var introductionOverlay: some View \{[\s\S]*?ScrollView \{\s*introductionCard')) {
    $errors.Add('Language Soccer may scroll only its introduction card; the field composition must not scroll.')
}

$dragIntroductionKey = @(
    'Drag letters upward in the correct order to kick toward the goal.',
    'A goal with the right letter earns you a point.',
    'Missing or being saved with a wrong letter gives the keeper a point.',
    'The round continues until the word is complete.'
) -join [char]10
$tapIntroductionKey = @(
    'Tap letters in the correct order to kick toward the goal.',
    'A goal with the right letter earns you a point.',
    'Missing or being saved with a wrong letter gives the keeper a point.',
    'The round continues until the word is complete.'
) -join [char]10
$catalogPolicies = @(
    @{ Path = 'Resources/Localization/All/Localizable.xcstrings'; Locales = @('am', 'ar', 'de', 'en', 'es', 'fr', 'he', 'nl', 'pt-BR', 'pt-PT', 'ru') },
    @{ Path = 'Resources/Localization/EnglishOnly/Localizable.xcstrings'; Locales = @('am', 'ar', 'de', 'en', 'es', 'fr', 'nl', 'pt-BR', 'pt-PT', 'ru') }
)
$dragTerms = @{
    'am' = '\u130e'; 'ar' = '\u0627\u0633\u062d\u0628'; 'de' = 'Zieht'; 'en' = 'Drag'; 'es' = 'Arrastra'
    'fr' = 'Faites glisser'; 'he' = '\u05d2\u05e8\u05e8\u05d5'; 'nl' = 'Sleep'; 'pt-BR' = 'Arraste'
    'pt-PT' = 'Arrasta'; 'ru' = '\u041f\u0435\u0440\u0435\u0442\u0430\u0441\u043a'
}
$tapTerms = @{
    'am' = '\u12ed\u1295\u12a9'; 'ar' = '\u0627\u0636\u063a\u0637'; 'de' = 'Tippt'; 'en' = 'Tap'; 'es' = 'Toca'
    'fr' = 'Touchez'; 'he' = '\u05dc\u05d7\u05e6\u05d5'; 'nl' = 'Tik'; 'pt-BR' = 'Toque'
    'pt-PT' = 'Toca'; 'ru' = '\u041d\u0430\u0436\u0438\u043c\u0430\u0439'
}

foreach ($policy in $catalogPolicies) {
    $catalog = Get-Content -LiteralPath (Join-Path $repoRoot $policy.Path) -Raw -Encoding utf8 | ConvertFrom-Json
    $entry = $catalog.strings.PSObject.Properties[$dragIntroductionKey].Value
    if ($null -eq $entry) {
        $errors.Add("Missing Soccer drag-introduction localization [$($policy.Path)]")
        continue
    }
    foreach ($locale in $policy.Locales) {
        $unit = $entry.localizations.PSObject.Properties[$locale].Value.stringUnit
        if ($unit.value -notmatch [regex]::Unescape($dragTerms[$locale])) {
            $errors.Add("Soccer introduction does not describe drag for locale $locale [$($policy.Path)]")
        }
        if ($unit.value -match [regex]::Unescape($tapTerms[$locale])) {
            $errors.Add("Soccer drag introduction still describes tap for locale $locale [$($policy.Path)]")
        }
        $expectedState = if ($locale -eq 'en') { 'translated' } else { 'needs_review' }
        if ($unit.state -ne $expectedState) {
            $errors.Add("Soccer introduction locale $locale has state '$($unit.state)'; expected '$expectedState'")
        }
    }
    $tapEntry = $catalog.strings.PSObject.Properties[$tapIntroductionKey].Value
    if ($null -eq $tapEntry) {
        $errors.Add("Missing shared Soccer tap-introduction localization [$($policy.Path)]")
        continue
    }
    foreach ($locale in $policy.Locales) {
        $unit = $tapEntry.localizations.PSObject.Properties[$locale].Value.stringUnit
        if ($unit.value -notmatch [regex]::Unescape($tapTerms[$locale])) {
            $errors.Add("Shared Soccer introduction does not describe tap for locale $locale [$($policy.Path)]")
        }
        if ($unit.value -match [regex]::Unescape($dragTerms[$locale])) {
            $errors.Add("Shared Soccer tap introduction still describes drag for locale $locale [$($policy.Path)]")
        }
        $expectedState = if ($locale -eq 'en') { 'translated' } else { 'needs_review' }
        if ($unit.state -ne $expectedState) {
            $errors.Add("Shared Soccer introduction locale $locale has state '$($unit.state)'; expected '$expectedState'")
        }
    }
}

$localeChecks = 2 * ($catalogPolicies | ForEach-Object { $_.Locales.Count } | Measure-Object -Sum).Sum
Write-Output "LANGUAGE_SOCCER_CONTRACTS_AUDITED=$($checks.Count + 2 + $localeChecks)"
Write-Output "LANGUAGE_SOCCER_CONTRACT_ERRORS=$($errors.Count)"
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Output 'LANGUAGE_SOCCER_AUDIT_OK'
