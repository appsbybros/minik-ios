$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$checks = @(
    @{ File = 'Sources/LearningSpeech.swift'; Pattern = 'speaker\.speak\(utterance'; Label = 'speech player invokes MinikSpeaker (recorded Hebrew, else AVSpeechSynthesizer)' },
    @{ File = 'Sources/LearningSpeech.swift'; Pattern = 'utterance\.voice = MinikSpeechVoice\.voice\(for: LearningSpeechVoiceLocale\.identifier'; Label = 'speech requests learned-language voice (the clearest installed) without silent guard' },
    @{ File = 'Sources/LearnView.swift'; Pattern = 'speechPlayer\.speak\(speechPlan\)'; Label = 'Learn invokes learned-language speech' },
    @{ File = 'Sources/LearnView.swift'; Pattern = '@Environment\(\\\.scenePhase\)'; Label = 'Learn stops speech on background' },
    @{ File = 'Sources/PairsView.swift'; Pattern = 'speechPlayer\.speak\(utterance\)'; Label = 'Pairs speaks the selected word' },
    @{ File = 'Sources/PairsView.swift'; Pattern = '@Environment\(\\\.scenePhase\)'; Label = 'Pairs stops speech on background' },
    @{ File = 'Sources/MultipleChoiceView.swift'; Pattern = 'selectedChoice\.learningSpeechCue'; Label = 'First Letter and matching choices invoke speech' },
    @{ File = 'Sources/MultipleChoiceView.swift'; Pattern = 'speakCurrentPrompt\(\)'; Label = 'First Letter and matching prompts invoke speech' },
    @{ File = 'Sources/MultipleChoiceView.swift'; Pattern = 'mathActivityFamily == nil'; Label = 'Multiple Choice does not route Math through Language speech' },
    @{ File = 'Sources/MultipleChoiceView.swift'; Pattern = '@Environment\(\\\.scenePhase\)'; Label = 'Multiple Choice stops speech on background' },
    @{ File = 'Sources/BuildView.swift'; Pattern = 'token\.representation\.learningSpeechCue'; Label = 'Build Word speaks selected tokens' },
    @{ File = 'Sources/BuildView.swift'; Pattern = 'speakCurrentPrompt\(\)'; Label = 'Build Word invokes prompt and replay speech' },
    @{ File = 'Sources/BuildView.swift'; Pattern = 'mathActivityFamily == nil'; Label = 'Build does not route Math through Language speech' },
    @{ File = 'Sources/BuildView.swift'; Pattern = '@Environment\(\\\.scenePhase\)'; Label = 'Build stops speech on background' },
    @{ File = 'Sources/CardsView.swift'; Pattern = 'speechPlayer\.speak\(speechPlan\)'; Label = 'Word Cards invokes card speech and replay' },
    @{ File = 'Sources/CardsView.swift'; Pattern = '@Environment\(\\\.scenePhase\)'; Label = 'Word Cards stops speech on background' },
    @{ File = 'Sources/LanguageSoccerView.swift'; Pattern = 'session\.selectedOrderedTokenSpeechCue'; Label = 'Soccer speaks selected ordered tokens' },
    @{ File = 'Sources/LanguageSoccerView.swift'; Pattern = 'interfaceSpeechPlayer\.speak\([\s\S]*soccerIntroductionText'; Label = 'Soccer introduction invokes localized interface speech' },
    @{ File = 'Sources/LanguageSoccerView.swift'; Pattern = '@Environment\(\\\.scenePhase\)'; Label = 'Soccer stops speech on background' },
    @{ File = 'Sources/TowerView.swift'; Pattern = 'lastAcceptedBlockSpeechCue'; Label = 'Tower speaks accepted ordered tokens' },
    @{ File = 'Sources/TowerView.swift'; Pattern = '@Environment\(\\\.scenePhase\)'; Label = 'Tower stops speech on background' },
    @{ File = 'Sources/MemoryView.swift'; Pattern = 'speechPlayer\.speak\(speechCue\)'; Label = 'Picture Memory speaks revealed words' },
    @{ File = 'Sources/MemoryView.swift'; Pattern = '@Environment\(\\\.scenePhase\)'; Label = 'Picture Memory stops speech on background' },
    @{ File = 'Sources/LanguageFirstLetterChoiceContentProvider.swift'; Pattern = 'speechCue: correctText\.learningSpeechCue'; Label = 'picture-to-letter image prompt carries word speech' },
    @{ File = 'Sources/LanguageFirstLetterPictureContentProvider.swift'; Pattern = 'speechCue: learnedText\.learningSpeechCue'; Label = 'letter-to-picture image choices carry word speech' },
    @{ File = 'Sources/LanguageWordContentProvider.swift'; Pattern = 'speechCue: learnedText\.learningSpeechCue'; Label = 'word-picture image choices carry word speech' },
    @{ File = 'Sources/LanguageWordBuildContentProvider.swift'; Pattern = 'speechCue: learnedText\.learningSpeechCue'; Label = 'Build Word image prompt carries word speech' }
)

$errors = [System.Collections.Generic.List[string]]::new()
foreach ($check in $checks) {
    $path = Join-Path $repoRoot $check.File
    $source = Get-Content -LiteralPath $path -Raw
    if ($source -notmatch $check.Pattern) {
        $errors.Add("Missing speech contract: $($check.Label) [$($check.File)]")
    }
}

Write-Output "LANGUAGE_SPEECH_CONTRACTS_AUDITED=$($checks.Count)"
Write-Output "LANGUAGE_SPEECH_CONTRACT_ERRORS=$($errors.Count)"
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Output 'LANGUAGE_SPEECH_STATIC_AUDIT_OK'
