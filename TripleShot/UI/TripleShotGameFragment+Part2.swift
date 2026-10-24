import Foundation

// Port of ui/TripleShotGameFragment.kt (Android 6c38131), lines 1950-3886: part 2 of the split class
// (DESIGN 2.9/2.10; spec 14-game2). Statement by statement, Kotlin names and member order kept.
//
// - Only methods, the nested `TutorialStep` enum (Kotlin L58-64, assigned to this part) and the companion object
//   live here. Every stored property of the Kotlin class is declared by part 1 (TripleShotGameFragment.swift).
//   Kotlin `private` members are internal (split class). Companion constants are `static let` members, read as
//   `TripleShotGameFragment.NAME` from instance code.
// - `override fun onDestroyView()` (Kotlin L3763) is `onDestroyView_impl()`; part 1 declares the forwarding
//   `override` stub (DESIGN 2.10).
// - Argument labels are the Kotlin parameter names (DESIGN 2.1).
// - Closures kept by views, the Handler, the court, the bot or Firebase capture `self` weakly (Android's GC
//   collects such cycles, ARC does not). Each of them re-checks `isAdded` / `ended` exactly like the Kotlin code,
//   so the behaviour is the same while the fragment exists.
// - Dead code kept (spec 14 section 1.2): `horseAttemptLabel` and `tapReviewText` are never called, as on Android.
// - No iOS-only control here: the exit control that replaces Android's system Back in every mode and phase
//   (spec 14 sections 8.22 and 10 Q6) is part 1's HUD exit button (`IOS_EXIT_BUTTON_ID`, DESIGN 12.3).

extension TripleShotGameFragment {

    /// Kotlin `private enum class TutorialStep` (L58-64). The ordinals 0-4 are the page numbers stored in
    /// `tutorialPage` / `tutorialProgress`.
    enum TutorialStep: String, KotlinEnum {
        case CHOOSE_ANSWER
        case AIM
        case PULL_BACK
        case THROW
        case FREE_PLAY
    }

    func showHorseQuestionForHuman(category: QuestionCategory) {
        let q = nextHorseQuestion(category: category)
        horseQuestion = q
        selectedAnswerIndex = -1
        knowledgeAnswerRecorded = false
        feedbackShowing = false
        feedbackText.visibility = AView.GONE

        categoryText.text =
            q.category.labelFor(
                languageCode: (AConfigurationCompat.getLocales(resources.configuration)[0] ?? ALocale.getDefault())
                    .language
            )
        questionText.text = readableQuestion(prompt: q.prompt)
        questionText.textSize = questionTextSizeFor(length: q.prompt.length)
        questionText.background = questionReadableBackground()
        if let outlined = questionText as? OutlinedTextView {
            outlined.setOutlineColor(color: AColor.rgb(18, 35, 48))
            outlined.setOutlineWidthDp(dp: 0.45)
        }

        answerStrip.removeAllViews()
        answerViews.removeAll()
        addHorseAnswerViews(q: q)

        courtView.setHorseAnswerMode()
        courtView.randomizeBallSkin()
        sensor.prepareForAnswer()
        updateAnswerSelection()
        showQuestionUi()
    }

    func addHorseAnswerViews(q: TripleShotQuestion) {
        for (index, option) in q.answers.enumerated() {
            let accent = answerAccentColor(index: index)

            let tv = OutlinedTextView()
            let params = ALinearLayout.LayoutParams(
                ALinearLayout.LayoutParams.MATCH_PARENT,
                ALinearLayout.LayoutParams.WRAP_CONTENT
            )
            params.topMargin = dp(v: 4)
            params.bottomMargin = dp(v: 3)
            tv.layoutParams = params

            tv.minHeight = dp(v: q.answers.count >= 4 ? 36 : 39)
            tv.gravity = AGravity.START | AGravity.CENTER_VERTICAL
            tv.textAlignment = AView.TEXT_ALIGNMENT_VIEW_START
            tv.layoutDirection = ["he", "iw"].contains(resources.configuration.locales[0].language) ? AView.LAYOUT_DIRECTION_RTL : AView.LAYOUT_DIRECTION_LTR
            tv.setPadding(dp(v: 7), dp(v: 4), dp(v: 7), dp(v: 4))
            tv.maxLines = 3
            tv.ellipsize = ATextUtils.TruncateAt.END
            tv.text = answerDisplayText(index: index, text: option.text)
            tv.textSize = answerTextSizeFor(length: option.text.length, answerCount: q.answers.count)
            tv.textDirection = AView.TEXT_DIRECTION_LOCALE
            tv.setTextColor(AColor.rgb(18, 35, 48))
            tv.setOutlineColor(color: AColor.rgb(18, 35, 48))
            tv.setOutlineWidthDp(dp: 0.55)
            tv.setTypeface(tv.typeface, ATypeface.BOLD)
            tv.background = answerOutlineBackground(accentColor: accent, selected: false)
            tv.isClickable = true
            tv.isFocusable = true
            tv.setOnClickListener { [weak self] _ in self?.selectAnswer(index: index) }

            answerStrip.addView(tv)
            answerViews.append(tv)
        }
    }

    /**
     * Shows the answer choices again after a HORSE shot and makes the correct answer
     * unmistakable. This is used for both the human and MINIK.
     */
    func showAnswerReview(
        question: TripleShotQuestion,
        selectedIndex: Int
    ) {
        guard let correctIndex = question.answers.firstIndex(where: { $0.qualityPercent >= 100 }) else { return }

        if answerViews.count != question.answers.count {
            answerStrip.removeAllViews()
            answerViews.removeAll()
            addHorseAnswerViews(q: question)
        }

        for (index, textView) in answerViews.enumerated() {
            let option = question.answers[index]
            let isCorrect = index == correctIndex
            let isWrongSelection = selectedIndex >= 0 && selectedIndex != correctIndex && index == selectedIndex

            textView.isClickable = false
            textView.isFocusable = false
            textView.setAlpha(isCorrect || isWrongSelection ? 1 : 0.82)
            if isCorrect {
                textView.text = answerDisplayText(index: index, text: option.text, statusMark: "\u{2713}")
            } else if isWrongSelection {
                textView.text = answerDisplayText(index: index, text: option.text, statusMark: "\u{2717}")
            } else {
                textView.text = answerDisplayText(index: index, text: option.text)
            }
            if isCorrect {
                textView.background = horseAnswerReviewBackground(
                    strokeColor: AColor.rgb(34, 139, 82),
                    fillColor: AColor.rgb(107, 220, 145)
                )
            } else if isWrongSelection {
                textView.background = horseAnswerReviewBackground(
                    strokeColor: AColor.rgb(190, 55, 55),
                    fillColor: AColor.rgb(255, 145, 159)
                )
            } else {
                textView.background = answerOutlineBackground(
                    accentColor: answerAccentColor(index: index),
                    selected: false
                )
            }

            if let outlined = textView as? OutlinedTextView {
                outlined.setOutlineColor(color: AColor.rgb(18, 35, 48))
                outlined.setOutlineWidthDp(dp: isCorrect || isWrongSelection ? 0.8 : 0.5)
            }
        }
    }

    func showHorseAnswerReview(
        question: TripleShotQuestion,
        actor: HorseGameEngine.Player,
        answerCorrect: Bool
    ) {
        guard let correctIndex = question.answers.firstIndex(where: { $0.qualityPercent >= 100 }) else { return }

        // MINIK's question normally has no answer buttons while it is thinking. Build
        // them now, after the shot, so the player can read the question and right answer.
        if answerViews.count != question.answers.count {
            answerStrip.removeAllViews()
            answerViews.removeAll()
            addHorseAnswerViews(q: question)
        }

        for (index, textView) in answerViews.enumerated() {
            let option = question.answers[index]
            let isCorrect = index == correctIndex
            let isHumanWrongSelection =
                actor == HorseGameEngine.Player.HUMAN &&
                !answerCorrect &&
                index == selectedAnswerIndex

            textView.isClickable = false
            textView.isFocusable = false
            textView.setAlpha(isCorrect || isHumanWrongSelection ? 1 : 0.82)

            if isCorrect {
                textView.text = answerDisplayText(index: index, text: option.text, statusMark: "\u{2713}")
            } else if isHumanWrongSelection {
                textView.text = answerDisplayText(index: index, text: option.text, statusMark: "\u{2717}")
            } else {
                textView.text = answerDisplayText(index: index, text: option.text)
            }

            if isCorrect {
                textView.background = horseAnswerReviewBackground(
                    strokeColor: AColor.rgb(34, 139, 82),
                    fillColor: AColor.rgb(107, 220, 145)
                )
            } else if isHumanWrongSelection {
                textView.background = horseAnswerReviewBackground(
                    strokeColor: AColor.rgb(190, 55, 55),
                    fillColor: AColor.rgb(255, 145, 159)
                )
            } else {
                textView.background = answerOutlineBackground(
                    accentColor: answerAccentColor(index: index),
                    selected: false
                )
            }

            if let outlined = textView as? OutlinedTextView {
                outlined.setOutlineColor(color: AColor.rgb(18, 35, 48))
                outlined.setOutlineWidthDp(
                    dp: isCorrect || isHumanWrongSelection ? 0.8 : 0.5
                )
            }
        }
    }

    func nextHorseQuestion(category: QuestionCategory) -> TripleShotQuestion {
        horseQuestionCounter += 1
        // Kotlin Long arithmetic: `config.seed xor (counter.toLong() * 0x9E3779B9L) xor ordinal.toLong()`.
        let seed =
            config.seed ^
            (horseQuestionCounter.toLong() &* 0x9E3779B9) ^
            category.ordinal.toLong()

        let pool = TripleShotQuestionRepository.shuffled(
            seed: seed,
            categories: KLinkedSet([category])
        )

        let chosen =
            pool.firstOrNull { !horseRecentQuestionIds.contains($0.id) }
                ?? pool.first()

        // MutableList.remove(element): the first occurrence.
        if let existing = horseRecentQuestionIds.firstIndex(of: chosen.id) {
            horseRecentQuestionIds.remove(at: existing)
        }
        horseRecentQuestionIds.append(chosen.id)
        while horseRecentQuestionIds.count > TripleShotGameFragment.HORSE_RECENT_QUESTION_MEMORY {
            horseRecentQuestionIds.remove(at: 0)
        }

        return chosen
    }

    func performHorseHumanShot(
        skill: ShotSkill,
        pullBackAtRelease: Float
    ) {
        guard let q = horseQuestion else { return }
        guard let chosen = q.answers.getOrNull(selectedAnswerIndex) else { return }

        shotInProgress = true
        hideQuestionUiForShot()
        feedbackText.visibility = AView.GONE
        restoreUiLayering()

        courtView.animateHorseShot(
            skill: skill,
            pullBackAtRelease: pullBackAtRelease.coerceAtLeast(TripleShotGameFragment.MIN_SHOT_PULLBACK),
            hot: false
        ) { [weak self] shotResult in
            guard let self else { return }
            if !self.isAdded || self.ended { return }

            let answerCorrect = chosen.qualityPercent >= 100
            self.resolveHorseAttempt(
                actor: HorseGameEngine.Player.HUMAN,
                answerCorrect: answerCorrect,
                made: shotResult.outcome.made,
                correctAnswerText:
                    q.answers.first(where: { $0.qualityPercent >= 100 })?.text ?? ""
            )
        }
    }

    func runBotHorseAttempt(category: QuestionCategory) {
        guard let bot = botOpponent else { return }
        let q = nextHorseQuestion(category: category)
        horseQuestion = q

        categoryText.text = q.category.labelFor(
            languageCode: (AConfigurationCompat.getLocales(resources.configuration)[0] ?? ALocale.getDefault())
                .language
        )
        questionText.text = readableQuestion(prompt: q.prompt)
        questionText.textSize = questionTextSizeFor(length: q.prompt.length)
        questionText.background = questionReadableBackground()
        answerStrip.removeAllViews()
        answerViews.removeAll()
        showQuestionUi()

        let turn = bot.prepareTurn(question: q, shotZone: courtView.currentBotShotZone())
        let answerCorrect = turn.answerQualityPercent >= 100

        handler.postDelayed({ [weak self] in
            guard let self else { return }
            if !self.isAdded || self.ended { return }

            self.shotInProgress = true
            self.hideQuestionUiForShot()
            self.restoreUiLayering()

            self.courtView.animateBotShot(
                skill: turn.skill,
                pullBackAtRelease: turn.pullBack,
                hot: false
            ) { [weak self] shotResult in
                guard let self else { return }
                if !self.isAdded || self.ended { return }

                // HORSE deliberately does not call bot.recordShot(): the 60-second score engine
                // is a separate mode. Here the real physics result goes only into HorseGameEngine.
                self.resolveHorseAttempt(
                    actor: HorseGameEngine.Player.BOT,
                    answerCorrect: answerCorrect,
                    made: shotResult.outcome.made,
                    correctAnswerText:
                        q.answers.first(where: { $0.qualityPercent >= 100 })?.text ?? ""
                )
            }
        }, TripleShotGameFragment.HORSE_BOT_THINK_DELAY_MS)
    }

    func resolveHorseAttempt(
        actor: HorseGameEngine.Player,
        answerCorrect: Bool,
        made: Bool,
        correctAnswerText: String
    ) {
        guard let engine = horseEngine else { return }
        let resolution = engine.resolveAttempt(
            player: actor,
            answerCorrect: answerCorrect,
            made: made
        )

        restoreUiLayering()
        shotInProgress = false
        feedbackShowing = true
        courtView.setShotGuidesVisible(visible: false)
        showQuestionUi()
        if let question = horseQuestion {
            showHorseAnswerReview(
                question: question,
                actor: actor,
                answerCorrect: answerCorrect
            )
        }

        if made { courtView.celebrateHorseBasket(human: actor == HorseGameEngine.Player.HUMAN, dance: answerCorrect) }
        horseTurnMessage = horseResolutionShortText(resolution: resolution)
        updateHud()

        feedbackText.visibility = AView.VISIBLE
        feedbackText.maxLines = 20
        feedbackText.layoutDirection = ["he", "iw"].contains(resources.configuration.locales[0].language) ? AView.LAYOUT_DIRECTION_RTL : AView.LAYOUT_DIRECTION_LTR
        feedbackText.textDirection = ["he", "iw"].contains(resources.configuration.locales[0].language) ? AView.TEXT_DIRECTION_RTL : AView.TEXT_DIRECTION_LTR
        feedbackText.gravity = AGravity.START | AGravity.CENTER_VERTICAL
        feedbackText.textDirection = ["he", "iw"].contains(resources.configuration.locales[0].language) ? AView.TEXT_DIRECTION_RTL : AView.TEXT_DIRECTION_LTR
        feedbackText.setText(
            horseReadableAttemptFeedback(
                actor: actor,
                answerCorrect: answerCorrect,
                made: made,
                correctAnswerText: correctAnswerText,
                resolution: resolution
            ))

        if resolution.state.isGameOver {
            waitForTapToContinue { [weak self] in
                self?.endHorseGame(winner: resolution.state.winner)
            }
            return
        }

        waitForTapToContinue { [weak self] in
            self?.advanceHorseTurn()
        }
    }

    func readableQuestion(prompt: String) -> String {
        // Keep arithmetic left-to-right inside an otherwise right-to-left sentence.
        let colon = prompt.utf16.firstIndex(of: 0x3A).map { prompt.utf16.distance(from: prompt.utf16.startIndex, to: $0) } ?? -1
        if colon < 0 { return prompt }
        let expression = prompt.ksubstring(colon + 1).ktrim()
        // Kotlin `expression.all { it.isDigit() || it.isWhitespace() || it in "()+-*/×÷.=%" }` over UTF-16 chars.
        let allowed = Set("()+-*/×÷.=%".utf16)
        let readable = expression.utf16.allSatisfy { unit in
            if allowed.contains(unit) || kIsWhitespace(unit) { return true }
            guard let scalar = Unicode.Scalar(unit) else { return false }   // a surrogate is no digit
            return scalar.properties.generalCategory == .decimalNumber
        }
        return !expression.isEmpty && readable
            ? prompt.ksubstring(0, colon + 1) + " \u{2066}" + expression + "\u{2069}" : prompt
    }

    func horseReadableAttemptFeedback(
        actor: HorseGameEngine.Player, answerCorrect: Bool, made: Bool,
        correctAnswerText: String, resolution: HorseGameEngine.Resolution
    ) -> ACharSequence {
        let he = ["he", "iw"].contains(resources.configuration.locales[0].language)
        func tr(_ en: String, _ h: String) -> String { he ? h : en }
        let answer = answerCorrect ? tr("\u{2713} Correct answer", "\u{2713} תשובה נכונה") : tr("\u{2717} Wrong answer", "\u{2717} תשובה שגויה")
        let shot = made ? tr("\u{2713} Basket!", "\u{2713} סל!") : tr("\u{2717} Missed shot", "\u{2717} החטאה")
        let rows: [(String, Bool)] = [(answer, true), (tr("Correct answer: ", "התשובה הנכונה: ") + correctAnswerText, false),
            (shot, true), (horseResolutionLongText(actor: actor, resolution: resolution), false), (tapToContinueHint(), true)]
        // SpannableStringBuilder: the text first, then one AlignmentSpan.Standard per row (UTF-16 ranges).
        var text = ""
        var ranges: [(Int, Int, Bool)] = []
        for (i, (row, center)) in rows.enumerated() {
            let start = text.length; text += row
            ranges.append((start, text.length, center))
            if i < rows.count - 1 { text += "\n" }
        }
        let result = ASpannableString(text)
        for (start, end, center) in ranges {
            result.setSpan(AAlignmentSpan.Standard(center ? ALayout.Alignment.ALIGN_CENTER : ALayout.Alignment.ALIGN_NORMAL),
                           start, end, ASpanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        return result
    }

    /// Never called (as on Android; spec 14 section 1.2).
    func horseAttemptLabel(answerCorrect: Bool, made: Bool) -> String {
        if answerCorrect && made { return getString(R.string.minik_swish_horse_correct_make) }
        if answerCorrect { return getString(R.string.minik_swish_horse_correct_miss) }
        if made { return getString(R.string.minik_swish_horse_wrong_make) }
        return getString(R.string.minik_swish_horse_wrong_miss)
    }

    func horseResolutionLongText(
        actor: HorseGameEngine.Player,
        resolution: HorseGameEngine.Resolution
    ) -> String {
        let human = actor == HorseGameEngine.Player.HUMAN
        let botName = currentBotDisplayName()

        switch resolution.type {
        case .CHALLENGE_ESTABLISHED:
            if human {
                return getString(
                    R.string.minik_swish_horse_challenge_established_you,
                    botName
                )
            } else {
                return getString(currentBotGenderedString(maleRes: R.string.minik_swish_horse_challenge_established_bot_male, femaleRes: R.string.minik_swish_horse_challenge_established_bot_female, neutralRes: R.string.minik_swish_horse_challenge_established_bot_neutral), botName)
            }

        case .SETTER_FAILED:
            if human {
                return getString(
                    R.string.minik_swish_horse_setter_failed_you,
                    botName
                )
            } else {
                return getString(currentBotGenderedString(maleRes: R.string.minik_swish_horse_setter_failed_bot_male, femaleRes: R.string.minik_swish_horse_setter_failed_bot_female, neutralRes: R.string.minik_swish_horse_setter_failed_bot_neutral), botName)
            }

        case .CONTINUE_NO_PENALTY:
            if human {
                return getString(R.string.minik_swish_horse_continue_clean_you)
            } else {
                return getString(currentBotGenderedString(maleRes: R.string.minik_swish_horse_continue_clean_bot_male, femaleRes: R.string.minik_swish_horse_continue_clean_bot_female, neutralRes: R.string.minik_swish_horse_continue_clean_bot_neutral), botName)
            }

        case .CONTINUE_WITH_PENALTY:
            if human {
                return getString(R.string.minik_swish_horse_continue_penalty_you)
            } else {
                return getString(currentBotGenderedString(maleRes: R.string.minik_swish_horse_continue_penalty_bot_male, femaleRes: R.string.minik_swish_horse_continue_penalty_bot_female, neutralRes: R.string.minik_swish_horse_continue_penalty_bot_neutral), botName)
            }

        case .CHALLENGE_ENDED_NO_PENALTY:
            if human {
                return getString(R.string.minik_swish_horse_end_clean_you)
            } else {
                return getString(currentBotGenderedString(maleRes: R.string.minik_swish_horse_end_clean_bot_male, femaleRes: R.string.minik_swish_horse_end_clean_bot_female, neutralRes: R.string.minik_swish_horse_end_clean_bot_neutral), botName)
            }

        case .CHALLENGE_ENDED_WITH_PENALTY:
            if human {
                return getString(R.string.minik_swish_horse_end_penalty_you)
            } else {
                return getString(currentBotGenderedString(maleRes: R.string.minik_swish_horse_end_penalty_bot_male, femaleRes: R.string.minik_swish_horse_end_penalty_bot_female, neutralRes: R.string.minik_swish_horse_end_penalty_bot_neutral), botName)
            }

        case .GAME_OVER:
            if resolution.state.winner == HorseGameEngine.Player.HUMAN {
                return getString(R.string.minik_swish_horse_you_win, currentBotDisplayName())
            } else {
                return getString(currentBotGenderedString(maleRes: R.string.minik_swish_horse_bot_wins_male, femaleRes: R.string.minik_swish_horse_bot_wins_female, neutralRes: R.string.minik_swish_horse_bot_wins_neutral), botName)
            }
        }
    }

    func horseResolutionShortText(
        resolution: HorseGameEngine.Resolution
    ) -> String {
        switch resolution.type {
        case .CHALLENGE_ESTABLISHED:
            return getString(R.string.minik_swish_horse_short_established)
        case .SETTER_FAILED:
            return getString(R.string.minik_swish_horse_short_setter_failed)
        case .CONTINUE_NO_PENALTY:
            return getString(R.string.minik_swish_horse_short_continue)
        case .CONTINUE_WITH_PENALTY:
            return getString(R.string.minik_swish_horse_short_continue_penalty)
        case .CHALLENGE_ENDED_NO_PENALTY:
            return getString(R.string.minik_swish_horse_short_end)
        case .CHALLENGE_ENDED_WITH_PENALTY:
            return getString(R.string.minik_swish_horse_short_end_penalty)
        case .GAME_OVER:
            return getString(R.string.minik_swish_horse_short_game_over)
        }
    }

    func endHorseGame(winner: HorseGameEngine.Player?) {
        if ended { return }

        ended = true
        botOpponent?.stop()
        sensor.cancelShot()
        handler.removeCallbacksAndMessages(nil)
        courtView.setHorseFreeMoveEnabled(enabled: false)
        courtView.setHorseSpotPickerVisible(visible: false)
        courtView.setShotGuidesVisible(visible: false)

        let state = horseEngine?.snapshot()
        let humanPenalties = state?.humanPenalties ?? 0
        let botPenalties = state?.botPenalties ?? 0
        let humanWon = winner == HorseGameEngine.Player.HUMAN
        BasketballSoundscape.result(activity: requireActivity(), won: humanWon, challenge: true)
        persistentExit?.visibility = AView.GONE

        resultScoreText.text = humanWon ? "\u{1F3C6}" : "\u{1F916}"
        resultStatsText.text =
            getString(
                R.string.minik_swish_character_horse_penalties,
                humanPenalties,
                currentBotDisplayName(),
                botPenalties
            )
        if humanWon {
            resultRankText.text = getString(R.string.minik_swish_horse_you_win, currentBotDisplayName())
        } else {
            resultRankText.text = getString(currentBotGenderedString(maleRes: R.string.minik_swish_horse_bot_wins_male, femaleRes: R.string.minik_swish_horse_bot_wins_female, neutralRes: R.string.minik_swish_horse_bot_wins_neutral), currentBotDisplayName())
        }

        // Kotlin `view?.findViewById<MaterialButton>(R.id.resultLeaderboardButton)?.visibility = View.GONE`.
        let leaderboardButton: AView? = view?.findViewById(R.id.resultLeaderboardButton)
        leaderboardButton?.visibility = AView.GONE

        /*
         * Let the court own a short visible finish before the result card covers it:
         * winner jumps, loser sits, and a human victory gets moving colored spotlights.
         * This path is HORSE-only and never changes solo/practice/challenge rendering.
         */
        feedbackText.visibility = AView.GONE
        questionCard.visibility = AView.GONE
        answerStrip.visibility = AView.GONE
        resultOverlay.visibility = AView.GONE

        if winner != nil {
            courtView.startHorseMatchCelebration(humanWon: humanWon)
            restoreUiLayering()
            topHud.bringToFront()
        }

        handler.postDelayed({ [weak self] in
            guard let self else { return }
            if !self.isAdded { return }
            self.restoreUiLayering()
            self.resultOverlay.visibility = AView.VISIBLE
            self.resultOverlay.bringToFront()
        }, TripleShotGameFragment.HORSE_END_CELEBRATION_MS)
    }

    /// Not reproducible by design (includes `System.nanoTime()`).
    func horseVisualSeed(salt: Int) -> Int64 {
        return config.seed ^
            (horseQuestionCounter.toLong() &* 1009) ^
            (salt.toLong() &* 7919) ^
            ASystem.nanoTime()
    }

    func runBotResponse(question: TripleShotQuestion) {
        guard let bot = botOpponent else {
            feedbackShowing = false
            shotInProgress = false
            if shouldEndNow() {
                endGame()
            } else {
                questionIndex += 1
                showQuestion()
            }
            return
        }

        feedbackText.visibility = AView.GONE
        hideQuestionUiForShot()
        restoreUiLayering()

        /*
         * The bot really answers the same question. Its chosen answer maps to the exact same
         * answer station table as the human, so it no longer teleports to an unrelated easy
         * corner. Same answer = same shot location; different answer = that answer's location.
         */
        let answerPlan = bot.chooseAnswer(question: question)
        let botZone =
            courtView.shotZoneForAnswer(
                index: answerPlan.selectedAnswerIndex,
                answerCount: question.answers.count
            )
        let turn = bot.prepareTurn(question: question, shotZone: botZone, answerPlan: answerPlan)
        let hotDuringFlight = bot.snapshot().shootingStreak >= 3
        // `question.id.hashCode().toLong()`: the Int32 hash, sign-extended.
        let movementSeed =
            config.seed ^
            question.id.javaHashCode.toLong() ^
            (botTurnCounter.toLong() &* 977)

        // Kotlin local `fun launchVisibleBotShot()`; a closure so that `self` can be captured weakly.
        let launchVisibleBotShot: () -> Void = { [weak self] in
            guard let self else { return }
            self.courtView.animateBotShot(
                skill: turn.skill,
                pullBackAtRelease: turn.pullBack,
                hot: hotDuringFlight
            ) { [weak self] shotResult in
                guard let self else { return }
                if !self.isAdded || self.ended {
                    return
                }

                bot.recordShot(
                    turn: turn,
                    made: shotResult.outcome.made
                )

                let botState = bot.snapshot()
                self.courtView.setBotHotHand(active: botState.shootingStreak >= 3)
                self.restoreUiLayering()

                self.botTurnCounter += 1
                self.shotInProgress = false
                self.feedbackShowing = true
                self.showQuestionUi()
                self.showAnswerReview(
                    question: question,
                    selectedIndex: turn.selectedAnswerIndex
                )

                let botName = self.currentBotDisplayName()
                let correctAnswer =
                    question.answers
                        .kMaxBy { $0.qualityPercent }?
                        .text ?? ""
                let answerLine: String
                if turn.answerQualityPercent == 100 {
                    answerLine = self.getString(
                        R.string.minik_swish_feedback_named_bot_answer_correct,
                        botName
                    )
                } else if turn.answerQualityPercent > 0 {
                    answerLine = self.getString(
                        R.string.minik_swish_feedback_named_bot_answer_partial,
                        botName,
                        turn.answerQualityPercent
                    )
                } else {
                    answerLine = self.getString(
                        R.string.minik_swish_feedback_named_bot_answer_wrong,
                        botName,
                        correctAnswer
                    )
                }
                let shotLine: String
                if shotResult.outcome.made {
                    shotLine = self.getString(R.string.minik_swish_feedback_named_bot_made, botName)
                } else {
                    shotLine = self.getString(R.string.minik_swish_feedback_named_bot_missed, botName)
                }

                self.feedbackText.visibility = AView.VISIBLE
                self.feedbackText.maxLines = 8
                self.feedbackText.text =
                    "\(answerLine)\n\(shotLine)\n\n\(self.tapToContinueHint())"

                self.waitForTapToContinue { [weak self] in
                    guard let self else { return }
                    if self.shouldEndNow() {
                        self.endGame()
                    } else {
                        self.questionIndex += 1
                        self.showQuestion()
                    }
                }
            }
        }

        // Vacate the bot's answer spot first, then let the bot walk/dribble into its choice.
        courtView.moveHumanToChallengeWaitingSpot(
            avoidAnswerIndex: turn.selectedAnswerIndex,
            answerCount: question.answers.count,
            seed: movementSeed,
            animate: true
        ) { [weak self] in
            guard let self else { return }
            if !self.isAdded || self.ended { return }

            self.courtView.moveBotToAnswerStation(
                index: turn.selectedAnswerIndex,
                answerCount: question.answers.count,
                animate: true
            ) { [weak self] in
                guard let self else { return }
                if !self.isAdded || self.ended { return }
                launchVisibleBotShot()
            }
        }
    }

    func showHorseShotChoice() {
        let he = ["he", "iw"].contains(resources.configuration.locales[0].language)
        let prefs = requireContext().getSharedPreferences("basketball_controls", 0)
        let options = he ? ["זריקה עם קשת עזר", "זריקת קפיצה \u{2014} בלי קשת עזר"] : ["Shot with aiming arc", "Jump shot \u{2014} no aiming arc"]
        AAppCompatAlertDialog.Builder(requireContext())
            .setTitle(he ? "איך תרצו לזרוק?" : "Choose your shot")
            .setSingleChoiceItems(options, prefs.getBoolean("horseJump", false) ? 1 : 0) { [weak self] dialog, index in
                prefs.edit().putBoolean("horseJump", index == 1).apply(); self?.courtView.setHorseJumpShot(enabled: index == 1); dialog.dismiss()
            }
            .setNeutralButton(he ? "איך משחקים" : "How to play") { [weak self] _, _ in self?.startTutorial(replay: true) }
            .setNegativeButton(he ? "חזרה למשחק" : "Back to game", nil).show()
    }

    func addChallengeExitLink() {
        if persistentExit != nil { return }
        guard let root = view as? AViewGroup else { return }
        let exit = exitGameButton()
        if root is AConstraintLayout {
            let lp = AConstraintLayout.LayoutParams(-2, dp(v: 52))
            lp.bottomToBottom = AConstraintLayout.LayoutParams.PARENT_ID; lp.startToStart = AConstraintLayout.LayoutParams.PARENT_ID; lp.endToEnd = AConstraintLayout.LayoutParams.PARENT_ID
            lp.bottomMargin = dp(v: 20); lp.marginStart = dp(v: 16); lp.marginEnd = dp(v: 16)
            root.addView(exit, lp)
        } else {
            let lp = AFrameLayout.LayoutParams(-2, dp(v: 52), AGravity.BOTTOM | AGravity.CENTER_HORIZONTAL)
            lp.bottomMargin = dp(v: 20)
            root.addView(exit, lp)
        }
        persistentExit = exit; exit.bringToFront()
    }

    func exitGameButton() -> TripleShotButton {
        let button = TripleShotButton()
        button.text = getString(R.string.minik_swish_one_on_one_exit_game); button.textSize = 17; button.isAllCaps = false
        button.gravity = AGravity.CENTER; button.minHeight = dp(v: 48); button.setPadding(dp(v: 24), dp(v: 10), dp(v: 24), dp(v: 10)); button.setTextColor(AColor.WHITE)
        FamilySkyUi.button(button: button, colors: AColorStateList.valueOf(argbInt(0xffe91e63)))
        button.setOnClickListener { [weak self] _ in self?.leaveGameToHome() }
        return button
    }

    func buildFeedback(
        q: TripleShotQuestion,
        quality: Int,
        shotResult: TripleShotCourtView.ShotResult,
        points: Int,
        multiplier: Int
    ) -> String {
        let correctAnswer =
            q.answers
                .kMaxBy { $0.qualityPercent }?
                .text ?? ""

        let answerPart: String
        if quality == 100 {
            answerPart = getString(R.string.minik_swish_feedback_answer_correct, multiplier)
        } else if quality > 0 {
            answerPart = getString(R.string.minik_swish_feedback_answer_partial, quality)
        } else {
            answerPart = getString(R.string.minik_swish_feedback_answer_wrong, correctAnswer)
        }

        let shotPart: String
        switch shotResult.kind {
        case .SWISH:
            shotPart = getString(R.string.minik_swish_feedback_shot_swish)

        case .RIM_IN:
            shotPart = getString(R.string.minik_swish_feedback_shot_rim_in)

        case .BANK_IN:
            shotPart = getString(R.string.minik_swish_feedback_shot_bank_in)

        case .RIM_OUT:
            shotPart = getString(R.string.minik_swish_feedback_shot_rim_out)

        case .BACKBOARD_OUT:
            shotPart = getString(R.string.minik_swish_feedback_shot_backboard_out)

        case .AIRBALL:
            shotPart = getString(R.string.minik_swish_feedback_shot_airball)

        case .INVALID_BELOW:
            shotPart = getString(R.string.minik_swish_feedback_shot_invalid_below)
        }

        let pointsPart = getString(R.string.minik_swish_feedback_points, points)
        return "\(answerPart)   \(shotPart)   \(pointsPart)\n\(q.explanation)\n\n\(tapToContinueHint())"
    }

    func publishLiveShotGesture(
        skill: ShotSkill,
        pullBackAtRelease: Float,
        hotDuringFlight: Bool
    ) {
        guard let room = config.roomId else { return }
        guard let uid = firebase.currentUid() else { return }
        let sourceSpot = courtView.currentPlayerSourcePosition()

        firebase.publishLiveShot(
            roomCodeRaw: room,
            event: LiveShotEvent(
                playerUid: uid,
                playerName: config.playerName,
                shotSpotX: sourceSpot.x,
                shotSpotY: sourceSpot.y,
                aimError: skill.aimError,
                powerError: skill.powerError,
                arcError: skill.arcError,
                rawPeakGyro: skill.rawPeakGyro,
                rawReleasePitchDeg: skill.rawReleasePitchDeg,
                pullBack: pullBackAtRelease.coerceAtLeast(TripleShotGameFragment.MIN_SHOT_PULLBACK),
                hotHand: hotDuringFlight,
                releasedAt: ASystem.currentTimeMillis()
            )
        )
    }

    func publishLiveState(
        quality: Int,
        made: Bool
    ) {
        guard let room =
            config.roomId else { return }

        let uid =
            firebase.currentUid() ?? ""

        // Hebrew in every locale: other devices show `lastEvent` verbatim (spec 14 section 4.11).
        let event: String
        if quality == 100 && made {
            event = "ענה נכון וקלע \u{1F525}"
        } else if quality == 100 {
            event = "ענה נכון, החטיא"
        } else if made {
            event = "קלע, אבל טעה בתשובה"
        } else {
            event = "החטיא וטעה"
        }

        firebase.updateLiveState(
            roomCodeRaw: room,
            state: LivePlayerState(
                uid: uid,
                name: config.playerName,
                score: scoring.totalScore,
                knowledgeStreak: scoring.knowledgeStreak,
                shootingStreak: scoring.shootingStreak,
                bestKnowledgeStreak: scoring.bestKnowledgeStreak,
                bestShootingStreak: scoring.bestShootingStreak,
                correctAnswers: scoring.correctAnswers,
                madeShots: scoring.madeShots,
                shots: scoring.shots,
                lastEvent: event
            )
        )
    }

    func configureCenteredQuestionLayout() {
        let params = questionCard.layoutParams
        if let params = params as? AConstraintLayout.LayoutParams {
            params.width = 0
            params.startToStart = AConstraintLayout.LayoutParams.PARENT_ID
            params.endToEnd = AConstraintLayout.LayoutParams.PARENT_ID
            // Kotlin `-1` = ConstraintLayout.LayoutParams.UNSET (AndroidKit anchors are view-id strings).
            params.leftToLeft = AConstraintLayout.LayoutParams.UNSET
            params.rightToRight = AConstraintLayout.LayoutParams.UNSET
            params.horizontalBias = 0.5
            params.matchConstraintPercentWidth = TripleShotGameFragment.QUESTION_CARD_WIDTH_PERCENT
            params.matchConstraintMaxWidth = dp(v: 560)
            params.marginStart = dp(v: 10)
            params.marginEnd = dp(v: 10)
            params.topMargin = dp(v: 7)
            questionCard.layoutParams = params
        }
    }

    func installTapToContinueOverlay(root: AView) {
        guard let parent = root as? AViewGroup else { return }
        if feedbackTapOverlay != nil { return }

        let overlay = AFrameLayout()
        overlay.visibility = AView.GONE
        overlay.isClickable = true
        overlay.isFocusable = true
        overlay.setBackgroundColor(AColor.TRANSPARENT)
        overlay.setOnClickListener { [weak self] _ in self?.continueAfterFeedback() }

        let exitParams = AFrameLayout.LayoutParams(-2, dp(v: 52), AGravity.BOTTOM | AGravity.CENTER_HORIZONTAL)
        exitParams.bottomMargin = dp(v: 20); exitParams.marginEnd = dp(v: 16); exitParams.marginStart = dp(v: 16)
        overlay.addView(exitGameButton(), exitParams)

        if parent is AConstraintLayout {
            let lp = AConstraintLayout.LayoutParams(0, 0)
            lp.startToStart = AConstraintLayout.LayoutParams.PARENT_ID
            lp.endToEnd = AConstraintLayout.LayoutParams.PARENT_ID
            lp.topToTop = AConstraintLayout.LayoutParams.PARENT_ID
            lp.bottomToBottom = AConstraintLayout.LayoutParams.PARENT_ID
            parent.addView(overlay, lp)
        } else {
            parent.addView(
                overlay,
                AViewGroup.LayoutParams(
                    AViewGroup.LayoutParams.MATCH_PARENT,
                    AViewGroup.LayoutParams.MATCH_PARENT
                )
            )
        }

        feedbackTapOverlay = overlay
    }

    func waitForTapToContinue(action: @escaping () -> Void) {
        feedbackContinueAction = action
        feedbackShowing = true
        if let overlay = feedbackTapOverlay {
            overlay.visibility = AView.VISIBLE
            overlay.bringToFront()
        }
    }

    func continueAfterFeedback() {
        if !feedbackShowing || ended { return }
        guard let action = feedbackContinueAction else { return }

        feedbackContinueAction = nil
        feedbackTapOverlay?.visibility = AView.GONE
        feedbackShowing = false
        feedbackText.visibility = AView.GONE
        action()
    }

    func tapToContinueHint() -> String {
        if ["he", "iw"].contains((AConfigurationCompat.getLocales(resources.configuration)[0] ?? ALocale.getDefault()).language) {
            return "לחצו בכל מקום כדי להמשיך"
        } else {
            return "Tap anywhere to continue"
        }
    }

    /// Never called (as on Android; spec 14 section 1.2).
    func tapReviewText(hebrew: String, english: String) -> String {
        return (["he", "iw"].contains((AConfigurationCompat.getLocales(resources.configuration)[0] ?? ALocale.getDefault()).language) ? hebrew : english) +
            "\n\n" + tapToContinueHint()
    }

    func showQuestionUi() {
        if questionCard == nil { return }

        // CourtView temporarily comes to the front during a flying ball. Put the readable
        // question layer back on top every time a new question appears so the player model
        // can never hide an answer before selection.
        restoreUiLayering()
        questionCard.bringToFront()
        questionCard.visibility = AView.VISIBLE
        questionCard.animate().cancel()
        questionCard.animate()
            .alpha(1)
            .setDuration(TripleShotGameFragment.UI_FADE_IN_MS)
            .start()

        for answerView in answerViews { answerView.isClickable = selectedAnswerIndex < 0 }
    }

    func fadeQuestionUiForAiming() {
        if questionCard == nil { return }

        for answerView in answerViews { answerView.isClickable = false }
        questionCard.animate().cancel()
        questionCard.animate()
            .alpha(TripleShotGameFragment.AIMING_UI_ALPHA)
            .setDuration(TripleShotGameFragment.UI_FADE_AIM_MS)
            .start()
    }

    func hideQuestionUiForShot() {
        if questionCard == nil { return }

        for answerView in answerViews { answerView.isClickable = false }
        questionCard.animate().cancel()
        questionCard.animate()
            .alpha(0)
            .setDuration(TripleShotGameFragment.UI_FADE_SHOT_MS)
            .start()
    }

    /**
     * Transparent answer capsule: only a thin colored outline in normal state.
     * Selection adds a very light tint but never blocks the forest / court artwork.
     */
    func answerOutlineBackground(
        accentColor: Int,
        selected: Bool
    ) -> AGradientDrawable {
        let drawable = FamilySkyDrawable()
        drawable.shape = AGradientDrawable.RECTANGLE
        drawable.cornerRadius = dp(v: 11).toFloat()

        // V13: readable at a glance under a 60-second clock, but still lets the artwork
        // show through. Selection gets a slightly warmer/stronger tint.
        drawable.setColor(
            selected ? AColor.argb(232, 255, 247, 220) : AColor.argb(214, 255, 252, 242)
        )
        drawable.setStroke(
            dp(v: selected ? 2 : 1),
            selected ? accentColor : AColor.argb(220, AColor.red(accentColor), AColor.green(accentColor), AColor.blue(accentColor))
        )
        return drawable
    }

    func horseAnswerReviewBackground(
        strokeColor: Int,
        fillColor: Int
    ) -> AGradientDrawable {
        let drawable = FamilySkyDrawable()
        drawable.shape = AGradientDrawable.RECTANGLE
        drawable.cornerRadius = dp(v: 11).toFloat()
        drawable.setColor(fillColor)
        drawable.setStroke(dp(v: 2), strokeColor)
        return drawable
    }

    func questionReadableBackground() -> AGradientDrawable {
        let drawable = FamilySkyDrawable()
        drawable.shape = AGradientDrawable.RECTANGLE
        drawable.cornerRadius = dp(v: 12).toFloat()
        drawable.setColor(AColor.argb(224, 255, 252, 242))
        drawable.setStroke(dp(v: 1), AColor.argb(205, 35, 60, 74))
        return drawable
    }

    func answerAccentColor(index: Int) -> Int {
        switch index % 4 {
        case 0: return AColor.rgb(232, 137, 31)   // A - orange
        case 1: return AColor.rgb(43, 119, 196)   // B - blue
        case 2: return AColor.rgb(181, 66, 146)   // C - magenta
        default: return AColor.rgb(35, 145, 94)   // D - green
        }
    }

    func questionTextSizeFor(length: Int) -> Float {
        if length <= 58 { return 18.2 }
        if length <= 92 { return 17.2 }
        if length <= 130 { return 16.2 }
        return 15.2
    }

    func answerTextSizeFor(
        length: Int,
        answerCount: Int
    ) -> Float {
        let base: Float
        switch answerCount {
        case 4: base = 13.4
        case 3: base = 14.0
        default: base = 14.5
        }

        if length > 82 { return base - 1.0 }
        if length > 56 { return base - 0.5 }
        return base
    }

    /**
     * Keeps the Android three-button navigation bar readable on devices where the
     * default theme gives us a light bar with light icons. The status bar is left
     * untouched; only the bottom system navigation area is styled to match the game.
     */
    func configureNavigationBar() {
        let window = requireActivity().window

        window.navigationBarColor = AColor.parseColor("#101820")
        AWindowCompat.getInsetsController(
            window,
            window.decorView
        ).isAppearanceLightNavigationBars = false

        // `Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q`: always true (AndroidKit models a current Android).
        window.isNavigationBarContrastEnforced = false
    }

    /**
     * Android HUD and controls remain above the opaque GPU world in every gameplay phase.
     */
    func restoreUiLayering() {
        if !isAdded { return }

        topHud.bringToFront()
        opponentsScroll.bringToFront()
        streakText.bringToFront()
        feedbackText.bringToFront()
        questionCard.bringToFront()
        answerStrip.bringToFront()
        tutorialCard.bringToFront()
        resultOverlay.bringToFront()
    }

    func horseScoreLabel(label: ATextView, name: String, count: Int) -> ACharSequence {
        // Keep the earned letters on their own visible row, even for long roster names.
        let score = " \(count)/5"
        let width = (label.width - label.compoundPaddingLeft - label.compoundPaddingRight).toFloat()
        let available = (width - label.paint.measureText(score) - 2 * resources.displayMetrics.density).coerceAtLeast(0)
        let shortName = width > 0 ? ATextUtils.ellipsize(name, label.paint, available, ATextUtils.TruncateAt.END) : name
        label.contentDescription = "\(name) \(count)/5, " + "HORSE".ktake(count.coerceIn(0, 5))
        let prefix = "\(shortName)\(score)\n"
        let text = ASpannableString(prefix + "HORSE")
        let colors = [argbInt(0xffff9f43), argbInt(0xff3498db), argbInt(0xffff5b67), argbInt(0xff158569), argbInt(0xffd49b00)]
        for i in kuntil(0, 5) {
            text.setSpan(AForegroundColorSpan(i < count ? colors[i] : AColor.BLACK), prefix.length + i, prefix.length + i + 1, ASpanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        return text
    }

    func updateHud() {
        if isLiveHorseMode() {
            let state = liveHorseState
            let myUid = firebase.currentUid() ?? ""
            timeText.text = getString(R.string.minik_swish_bot_mode_horse)
            scoreText.text = "\(liveHorseText(hebrew: "אני", english: "You")) \(state?.penalties[myUid] ?? 0)/5"
            botScoreText.visibility = AView.GONE
            if let state {
                if !state.winnerUid.kotlinIsBlank {
                    streakText.text = liveHorseText(hebrew: "המשחק הסתיים", english: "Match finished")
                } else if state.spectatorSlots[myUid] != nil {
                    streakText.text = liveHorseText(hebrew: "צופים", english: "Spectating")
                } else if state.currentPlayerUid == myUid {
                    streakText.text = liveHorseText(hebrew: "התור שלכם", english: "Your turn")
                } else {
                    let currentPlayer = latestLivePlayers.first(where: { $0.uid == state.currentPlayerUid })
                    let name: String
                    if let currentPlayer {
                        name = currentPlayer.name.kotlinIsBlank ? "Player" : currentPlayer.name
                    } else {
                        name = "Player"
                    }
                    streakText.text = liveHorseText(hebrew: "התור של \(name)", english: "\(name)'s turn")
                }
            } else {
                streakText.text = liveHorseText(hebrew: "מתחבר לחדר\u{2026}", english: "Connecting\u{2026}")
            }
            ballsText.visibility = AView.GONE
            return
        }

        if isBotHorseMode() {
            let state = horseEngine?.snapshot()
            timeText.text = getString(R.string.minik_swish_bot_mode_horse)
            scoreText.setSingleLine(false); scoreText.maxLines = 2; scoreText.setTextColor(argbInt(0xff158569))
            scoreText.setText(horseScoreLabel(label: scoreText, name: liveHorseText(hebrew: "אני", english: "You"), count: state?.humanPenalties ?? 0))
            botScoreText.visibility = AView.VISIBLE
            botScoreText.setSingleLine(false); botScoreText.maxLines = 2; botScoreText.setTextColor(argbInt(0xffff5b67))
            botScoreText.setText(horseScoreLabel(label: botScoreText, name: currentBotDisplayName(), count: state?.botPenalties ?? 0))
            streakText.text = horseTurnMessage
            ballsText.visibility = AView.GONE
            return
        }

        /*
         * V18: one thin, always-readable HUD row at the very top.
         * Bot streaks are intentionally not shown; only the player's two streaks remain.
         * The separate TextViews also avoid RTL/BiDi reordering of Hebrew, numbers and emoji.
         */
        if isPracticeMode() {
            timeText.text = liveHorseText(hebrew: "אימון", english: "Practice")
        } else if config.limitMode == GameLimitMode.BALLS_ONLY {
            timeText.text = "\u{23F1} --"
        } else {
            timeText.text = "\u{23F1} \(secondsLeft.coerceAtLeast(0))"
        }

        if config.isBotMatch || config.isMultiplayer {
            scoreText.text = "\(liveHorseText(hebrew: "אני", english: "You")) \(scoring.totalScore)"
        } else {
            scoreText.text = "\(liveHorseText(hebrew: "ניקוד", english: "Score")) \(scoring.totalScore)"
        }

        let botState = botOpponent?.snapshot()
        botScoreText.visibility =
            config.isBotMatch ? AView.VISIBLE : AView.GONE
        if config.isBotMatch {
            let botName: String
            if let botState {
                botName = botState.name.kotlinIsBlank ? currentBotDisplayName() : botState.name
            } else {
                botName = currentBotDisplayName()
            }
            botScoreText.text = "\(botName) \(botState?.score ?? 0)"
        } else {
            botScoreText.text = ""
        }

        streakText.text =
            "\u{1F9E0} \(scoring.knowledgeStreak)    \u{1F3C0} \(scoring.shootingStreak)"

        /*
         * Shot count is useful in unlimited Practice / ball-limited modes, but it must not
         * create a second HUD row in the 60-second challenge.
         */
        let showBalls =
            isPracticeMode() || config.limitMode == GameLimitMode.BALLS_ONLY
        ballsText.visibility = showBalls ? AView.VISIBLE : AView.GONE
        if isPracticeMode() {
            ballsText.text = "זריקות \(scoring.shots)"
        } else {
            ballsText.text = "\u{1F3C0} \(scoring.shots)/\(config.ballLimit)"
        }
    }

    /** Practice is intentionally unlimited. The player leaves when they are done. */
    func shouldEndNow() -> Bool {
        if isPracticeMode() || isAnyHorseMode() { return false }

        let ballsDone =
            config.limitMode != GameLimitMode.TIME_ONLY &&
            scoring.shots >= config.ballLimit

        let timeDone =
            config.limitMode != GameLimitMode.BALLS_ONLY &&
            secondsLeft <= 0

        return ballsDone || timeDone
    }

    /**
     * Shared exit path for the Android Back button and the result-screen Home button.
     * Marking the game as ended before navigating prevents a delayed shot/bot/feedback
     * callback from trying to update this Fragment while the host is returning home.
     */
    func leaveGameToHome() {
        if !isAdded { return }

        ended = true
        shotInProgress = false
        feedbackShowing = false
        handler.removeCallbacksAndMessages(nil)
        botOpponent?.stop()
        if sensor != nil {
            sensor.cancelShot()
        }
        if let room = config.roomId {
            firebase.leaveRoomAndCleanupIfLast(roomCodeRaw: room)
        }

        (parentFragment as? TripleShotHostFragment)?.backToHome()
    }

    func isPracticeMode() -> Bool {
        return config.isPractice
    }

    func endGame() {
        if ended { return }

        ended = true
        persistentExit?.visibility = AView.GONE

        botOpponent?.stop()
        sensor.cancelShot()
        handler.removeCallbacksAndMessages(nil)
        feedbackContinueAction = nil; feedbackShowing = false
        feedbackTapOverlay?.visibility = AView.GONE
        questionCard.animate().cancel(); questionCard.visibility = AView.GONE
        answerStrip.visibility = AView.GONE; feedbackText.visibility = AView.GONE
        tutorialActive = false; tutorialCard.visibility = AView.GONE

        // `(100f * correctAnswers / shots).roundToInt()`: Float maths, then Math.round.
        let accuracy =
            scoring.shots == 0
                ? 0
                : (Float(100) * scoring.correctAnswers.toFloat() / scoring.shots.toFloat()).roundToInt()

        let shooting =
            scoring.shots == 0
                ? 0
                : (Float(100) * scoring.madeShots.toFloat() / scoring.shots.toFloat()).roundToInt()

        resultOverlay.visibility = AView.VISIBLE
        resultOverlay.bringToFront()

        resultScoreText.text =
            String(scoring.totalScore)

        let hebrew = ["he", "iw"].contains(resources.configuration.locales[0].language)
        resultStatsText.text = hebrew
            ? "\u{1F9E0} ידע: \(accuracy)% (\(scoring.correctAnswers)/\(scoring.shots))\n\u{1F3C0} קליעות: \(shooting)% (\(scoring.madeShots)/\(scoring.shots))\n\u{1F525} רצף ידע: \(scoring.bestKnowledgeStreak) \u{2022} רצף קליעות: \(scoring.bestShootingStreak)"
            : "\u{1F9E0} Answers: \(accuracy)% (\(scoring.correctAnswers)/\(scoring.shots))\n\u{1F3C0} Baskets: \(shooting)% (\(scoring.madeShots)/\(scoring.shots))\n\u{1F525} Best answer streak: \(scoring.bestKnowledgeStreak) \u{2022} Basket streak: \(scoring.bestShootingStreak)"

        let botState = botOpponent?.snapshot()
        BasketballSoundscape.result(activity: requireActivity(), won: botState != nil ? scoring.totalScore > botState!.score : scoring.madeShots > 0, challenge: true)

        if config.isBotMatch, let botState {
            // Kotlin `resultStatsText.append(...)` (ATextView has no append; the visible text is the same).
            resultStatsText.text = resultStatsText.text +
                "\n\n" +
                getString(
                    R.string.minik_swish_opponent_score_line,
                    botState.name,
                    botState.score
                )

            if scoring.totalScore > botState.score {
                resultRankText.text = getString(
                    R.string.minik_swish_character_bot_result_win,
                    botState.name,
                    scoring.totalScore,
                    botState.score
                )
            } else if scoring.totalScore < botState.score {
                resultRankText.text = getString(
                    R.string.minik_swish_character_bot_result_loss,
                    botState.name,
                    scoring.totalScore,
                    botState.score
                )
            } else {
                resultRankText.text = getString(
                    R.string.minik_swish_character_bot_result_tie,
                    botState.name,
                    scoring.totalScore
                )
            }
        } else {
            // Hebrew in every locale (spec 14 section 6.3).
            if config.isMultiplayer {
                resultRankText.text = "מסכם את משחק הלייב..."
            } else if config.isRanked {
                resultRankText.text = "שומר תוצאה..."
            } else {
                resultRankText.text = "מצב אימון \u{2014} לא נכנס לדירוג"
            }
        }

        if config.isMultiplayer {
            publishLiveFinishedState()
            if let room = config.roomId {
                firebase.markRoomFinished(roomCodeRaw: room) { [weak self] _ in
                    guard let self else { return }
                    if self.isAdded {
                        self.firebase.armFinishedRoomCleanupIfLast(roomCodeRaw: room)
                    }
                }
            }
            renderLiveResult()
        }

        if config.isRanked {
            firebase.saveLeaderboardBest(
                playerName: config.playerName,
                score: scoring.totalScore,
                bestShootingStreak: scoring.bestShootingStreak,
                bestKnowledgeStreak: scoring.bestKnowledgeStreak,
                correctAnswers: scoring.correctAnswers,
                shots: scoring.shots,
                madeShots: scoring.madeShots,
                selectedCategories: config.selectedCategories
            ) { [weak self] saveResult in
                guard let self else { return }
                if !self.isAdded {
                    return
                }

                switch saveResult {
                case .success(let entry):
                    self.firebase.getScoreRank(
                        score: entry.bestScore
                    ) { [weak self] rankResult in
                        guard let self else { return }
                        if !self.isAdded {
                            return
                        }

                        switch rankResult {
                        case .success(let rank):
                            self.resultRankText.text = "השיא שלך: \(entry.bestScore) \u{2022} מיקום #\(rank)"
                        case .failure:
                            self.resultRankText.text = "השיא שלך: \(entry.bestScore)"
                        }
                    }
                case .failure:
                    self.resultRankText.text =
                        "לא ניתן היה לשמור דירוג כרגע"
                }
            }
        }
    }

    func publishLiveFinishedState() {
        guard let room = config.roomId else { return }
        firebase.updateLiveState(
            roomCodeRaw: room,
            state: LivePlayerState(
                uid: firebase.currentUid() ?? "",
                name: config.playerName,
                score: scoring.totalScore,
                knowledgeStreak: scoring.knowledgeStreak,
                shootingStreak: scoring.shootingStreak,
                bestKnowledgeStreak: scoring.bestKnowledgeStreak,
                bestShootingStreak: scoring.bestShootingStreak,
                correctAnswers: scoring.correctAnswers,
                madeShots: scoring.madeShots,
                shots: scoring.shots,
                lastEvent: "סיים",
                finished: true
            )
        )
    }

    func renderLiveResult() {
        if !config.isMultiplayer || resultRankText == nil { return }

        let myUid = firebase.currentUid() ?? ""
        let me = LivePlayerState(
            uid: myUid,
            name: config.playerName,
            score: scoring.totalScore
        )
        // filter + plus, then the stable `sortedByDescending { score }` and `take(4)`.
        let merged = Array(
            (latestLivePlayers.filter { $0.uid != myUid } + [me])
                .kSortedByDescending { $0.score }
                .prefix(4)
        )

        if merged.isEmpty { return }

        resultRankText.text =
            merged.enumerated().map { index, player in
                "\(index + 1). \(player.name.kotlinIsBlank ? "Player" : player.name) \u{2014} \(player.score)"
            }.joined(separator: "   \u{2022}   ")
    }

    /**
     * Starts the local visible opponent. The bot has no autonomous timer: it waits on court,
     * takes one real physics shot immediately after the human's shot, then walks to a new spot.
     * No Firebase traffic is used for a bot match.
     */
    func currentBotProfile() -> TripleShotCharacterProfile {
        return TripleShotCharacterRoster.find(id: config.botCharacterId)
            ?? TripleShotCharacterRoster.bob
    }

    func currentBotDisplayName() -> String {
        if let name = botOpponent?.snapshot().name, !name.kotlinIsBlank {
            return name
        }
        return currentBotProfile().displayName
    }

    /// Kotlin `neutralRes: Int = maleRes`: `nil` stands for "the male resource".
    func currentBotGenderedString(
        maleRes: AStringRes,
        femaleRes: AStringRes,
        neutralRes: AStringRes? = nil
    ) -> AStringRes {
        let neutralRes = neutralRes ?? maleRes
        switch currentBotProfile().gender {
        case .MALE: return maleRes
        case .FEMALE: return femaleRes
        case .NEUTRAL: return neutralRes
        }
    }

    func startBotOpponent() {
        let botProfile =
            TripleShotCharacterRoster.find(id: config.botCharacterId)
                ?? TripleShotCharacterRoster.bob

        let botDisplayName = botProfile.displayName

        let bot = TripleShotBotOpponent(
            displayName: botDisplayName,
            seed: config.seed,
            characterProfile: botProfile,
            onStateChanged: { [weak self] _ in
                guard let self else { return }
                if self.isAdded && !self.ended {
                    self.updateHud()
                }
            }
        )

        botOpponent = bot
        botTurnCounter = 0

        // Bot score lives only in the top HUD. The bottom opponent card is reserved for Live.
        opponentsContainer.removeAllViews()
        opponentsScroll.visibility = AView.GONE
        updateHud()

        courtView.setBotOpponentEnabled(
            enabled: true,
            seed: config.seed ^ TripleShotGameFragment.BOT_COURT_SEED_SALT,
            label: botDisplayName
        )

        // setBotOpponentEnabled() owns the generic local-bot setup and therefore gives the
        // freshly-created bot a visible held ball. In the 60-second challenge the human is the
        // first shooter, so normalize ownership immediately on the SAME UI turn. This prevents
        // the one-frame "two balls" flash before showQuestion() gets a chance to prepare the turn.
        if config.gameType == GameType.SHOOTING_CHALLENGE {
            courtView.prepareHumanChallengeTurn()
            // setBotOpponentEnabled() reposts itself when CourtView has not been laid out yet.
            // That deferred call used to re-enable the bot ball after the immediate normalization,
            // producing the visible one-frame "two balls" flash. Post one final normalization
            // behind that setup pass so the first rendered challenge frame has exactly one ball.
            courtView.post { [weak self] in
                guard let self else { return }
                if self.isAdded && !self.ended && self.config.gameType == GameType.SHOOTING_CHALLENGE {
                    self.courtView.prepareHumanChallengeTurn()
                }
            }
        }
        bot.start()
    }

    func subscribeOpponents() {
        guard let room = config.roomId else { return }

        opponentsScroll.visibility = AView.VISIBLE
        game2SetClear(&seenLiveShotIds)

        roomPlayersHandle =
            firebase.listenRoomPlayers(codeRaw: room) { [weak self] players in
                guard let self else { return }
                if !self.isAdded {
                    return
                }

                self.latestLivePlayers = players
                let myUid = self.firebase.currentUid()
                let opponents = Array(
                    players
                        .filter { $0.uid != myUid }
                        .prefix(3)
                )

                self.renderOpponents(players: opponents)
                if self.courtView != nil {
                    self.courtView.setLiveOpponents(players: opponents)
                    if self.isLiveHorseMode() {
                        if let state = self.liveHorseState {
                            self.courtView.applyLiveHorseState(
                                state: state,
                                myUid: self.firebase.currentUid() ?? ""
                            )
                        }
                    }
                }
                if self.isLiveHorseMode() {
                    if let state = self.liveHorseState { self.handleLiveHorseState(state: state) }
                }
                if self.ended && self.config.isMultiplayer {
                    self.renderLiveResult()
                    self.firebase.armFinishedRoomCleanupIfLast(roomCodeRaw: room)
                }
            }

        roomShotsHandle =
            firebase.listenLiveShots(roomCodeRaw: room) { [weak self] event in
                guard let self else { return }
                if !self.isAdded || self.ended || self.courtView == nil {
                    return
                }
                let myUid = self.firebase.currentUid()
                if event.playerUid == myUid {
                    return
                }
                if event.id.kotlinIsBlank || !game2SetAdd(&self.seenLiveShotIds, event.id) {
                    return
                }
                self.courtView.playLiveRemoteShot(event: event)
            }
    }

    func renderOpponents(
        players: [LivePlayerState]
    ) {
        opponentsContainer.removeAllViews()

        if players.isEmpty {
            opponentsScroll.visibility = AView.GONE
            return
        }

        opponentsScroll.visibility = AView.VISIBLE

        for p in players {
            // ContextCompat.getColor(requireContext(), R.color.triple_shot_ink)
            let inkColor =
                ContextCompat_getColor(
                    R.color.triple_shot_ink
                )

            let chip = ALinearLayout()
            chip.orientation = ALinearLayout.VERTICAL
            chip.gravity = AGravity.START
            chip.textDirection = AView.TEXT_DIRECTION_LOCALE

            chip.setBackgroundResource(
                R.drawable.triple_shot_panel
            )

            chip.setPadding(
                dp(v: 10),
                dp(v: 6),
                dp(v: 10),
                dp(v: 6)
            )

            let chipParams =
                ALinearLayout.LayoutParams(
                    ALinearLayout.LayoutParams.WRAP_CONTENT,
                    ALinearLayout.LayoutParams.WRAP_CONTENT
                )
            chipParams.marginEnd = dp(v: 6)
            chip.layoutParams = chipParams

            let scoreLine = ATextView()
            scoreLine.setTextColor(inkColor)
            scoreLine.textSize = 12.5
            scoreLine.gravity = AGravity.START
            scoreLine.textDirection = AView.TEXT_DIRECTION_LOCALE
            scoreLine.text =
                getString(
                    R.string.minik_swish_opponent_score_line,
                    p.name,
                    p.score
                )

            let streakLine = ATextView()
            streakLine.setTextColor(inkColor)
            streakLine.textSize = 11.5
            streakLine.gravity = AGravity.START
            streakLine.textDirection = AView.TEXT_DIRECTION_LOCALE
            streakLine.text =
                getString(
                    R.string.minik_swish_opponent_streaks_line,
                    p.knowledgeStreak,
                    p.shootingStreak
                )

            chip.addView(scoreLine)
            chip.addView(streakLine)

            if !p.lastEvent.kotlinIsBlank && p.lastEvent != "\u{2026}" {
                let lastEventLine = ATextView()
                lastEventLine.setTextColor(inkColor)
                lastEventLine.textSize = 11.5
                lastEventLine.gravity = AGravity.START
                lastEventLine.textDirection = AView.TEXT_DIRECTION_LOCALE
                lastEventLine.text = p.lastEvent
                chip.addView(lastEventLine)
            }

            opponentsContainer.addView(chip)
        }
    }

    /**
     * replay=true is intentionally read-only: it opens every help page without resetting
     * the current answer/shot. The small ? button can therefore be used safely at any time.
     */
    func startTutorial(replay: Bool) {
        if !isAdded || ended || shotInProgress { return }

        tutorialActive = true
        tutorialPage =
            TutorialStep.CHOOSE_ANSWER.ordinal

        tutorialProgress =
            replay
                ? TutorialStep.FREE_PLAY.ordinal
                : TutorialStep.CHOOSE_ANSWER.ordinal

        tutorialCard.visibility = AView.VISIBLE

        updateTutorialUi()
    }

    /**
     * Unlocks the next help page when the real game action has been demonstrated.
     *
     * If the player manually pressed "back" to reread an older page, we do NOT yank
     * them forward; the new page simply becomes available via the Next button.
     */
    func unlockTutorialStep(step: TutorialStep) {
        if !tutorialActive { return }

        let newProgress = step.ordinal
        if newProgress <= tutorialProgress { return }

        let previousProgress = tutorialProgress
        tutorialProgress = newProgress

        if tutorialPage == previousProgress {
            tutorialPage = newProgress
        }

        updateTutorialUi()
    }

    func finishTutorialPermanently() {
        tutorialPreferences
            .edit()
            .putBoolean(
                TripleShotGameFragment.TUTORIAL_DONE_KEY,
                true
            )
            .apply()

        tutorialActive = false
        hideTutorialCard()
    }

    func hideTutorialCard() {
        if tutorialCard != nil {
            tutorialCard.visibility = AView.GONE
        }
    }

    /// The texts are Hebrew in every locale (spec 14 section 6.3), including the "Next" label.
    func updateTutorialUi() {
        if !tutorialActive || !isAdded { return }

        tutorialCard.visibility = AView.VISIBLE

        let step =
            TutorialStep.allCases[
                tutorialPage.coerceIn(
                    0,
                    TutorialStep.allCases.count - 1
                )
            ]

        switch step {
        case .CHOOSE_ANSWER:
            tutorialTitle.text =
                "1/4 \u{2022} בחר תשובה"

            tutorialBody.text =
                "לחץ על התשובה שאתה חושב שנכונה. " +
                "השחקן יכדרר אוטומטית לעמדת הזריקה שלה."

        case .AIM:
            tutorialTitle.text =
                "2/4 \u{2022} כוון"

            tutorialBody.text =
                "אפשר לסובב מעט את הטלפון ימינה/שמאלה, " +
                "או לגרור ימינה/שמאלה בכל מקום על המגרש. " +
                "הנקודה ליד הסל מראה את כיוון הזריקה."

        case .PULL_BACK:
            tutorialTitle.text =
                "3/4 \u{2022} בנה קשת"

            tutorialBody.text =
                "הטה את הטלפון מעט לאחור, או גרור למטה/למעלה על המגרש. " +
                "במגע, המרחק של הגרירה קובע גם את הקשת וגם את עוצמת הבסיס: " +
                "מעט מדי נוטה להיות קצר, יותר מדי נוטה להיות חזק."

        case .THROW:
            tutorialTitle.text =
                "4/4 \u{2022} זרוק"

            tutorialBody.text =
                "במגע: כשמצאת כיוון וקשת שנראים לך טוב, פשוט שחרר. " +
                "Flick למעלה מוסיף עוד כוח, אבל הוא לא חובה. " +
                "עם המכשיר עצמו המהירות קדימה עדיין קובעת את הכוח."

        case .FREE_PLAY:
            tutorialTitle.text =
                "מעולה \u{1F3AF}"

            tutorialBody.text =
                "זה הכול: תשובה \u{2192} כיוון \u{2192} קשת/עוצמה \u{2192} זריקה. " +
                "במגע לומדים את נקודת הכוח דרך עומק הגרירה; " +
                "בחיישנים המהירות קדימה נותנת שליטה ידנית מלאה. " +
                "הכפתור ? פותח שוב את כל ההדרכה."
        }

        tutorialPrevButton.isEnabled =
            tutorialPage > TutorialStep.CHOOSE_ANSWER.ordinal

        tutorialPrevButton.setAlpha(
            tutorialPrevButton.isEnabled ? 1 : 0.35
        )

        tutorialNextButton.isEnabled =
            tutorialPage < tutorialProgress

        tutorialNextButton.setAlpha(
            tutorialNextButton.isEnabled ? 1 : 0.35
        )

        tutorialNextButton.text =
            tutorialPage >= TutorialStep.FREE_PLAY.ordinal
                ? "הבא"
                : "הבא \u{203A}"
    }

    /// `(v * resources.displayMetrics.density).roundToInt()`: Int * Float is a Float product, then Math.round.
    func dp(v: Int) -> Int {
        return (
            v.toFloat() *
                resources.displayMetrics.density
        )
            .roundToInt()
    }

    /// Body of `override fun onDestroyView()` (Kotlin L3763); part 1 declares the `override` stub.
    func onDestroyView_impl() {
        handler.removeCallbacksAndMessages(nil)

        roomPlayersHandle?.remove()
        roomPlayersHandle = nil
        roomShotsHandle?.remove()
        roomShotsHandle = nil
        liveHorseHandle?.remove()
        liveHorseHandle = nil

        botOpponent?.stop()
        botOpponent = nil

        feedbackContinueAction = nil
        persistentExit = nil
        feedbackTapOverlay = nil

        if courtView != nil {
            courtView.setBotOpponentEnabled(enabled: false)
            courtView.clearLiveOpponents()
            courtView.setOnTouchListener(nil)
        }

        super.onDestroyView()
    }

    // MARK: - companion object (Kotlin L3788-3885)

    static let STATION_TAP_SLOP_DP = 18
    static let HORSE_MOVE_TAP_SLOP_DP = 10
    static let ARG_NAME = "name"
    static let ARG_GAME_TYPE = "game_type"
    static let ARG_MODE = "mode"
    static let ARG_CATEGORIES = "categories"
    static let ARG_ROOM = "room"
    static let ARG_ROOM_STARTED_AT = "room_started_at"
    static let ARG_BOT_MATCH = "bot_match"
    static let ARG_PLAYER_CHARACTER = "player_character"
    static let ARG_BOT_CHARACTER = "bot_character"
    static let ARG_SEED = "seed"
    static let ARG_BALL_LIMIT = "ball_limit"
    static let ARG_TIME_LIMIT_SECONDS = "time_limit_seconds"

    static let TUTORIAL_PREFS =
        "minik_swish_tutorial"

    static let TUTORIAL_DONE_KEY =
        "shooting_tutorial_completed"

    static let TUTORIAL_AIM_MOVEMENT: Float = 0.18
    static let MIN_SHOT_PULLBACK: Float = 0.24

    static let AIMING_UI_ALPHA: Float = 0
    static let UI_FADE_AIM_MS: Int64 = 170
    static let UI_FADE_SHOT_MS: Int64 = 110
    static let UI_FADE_IN_MS: Int64 = 170

    static let BOT_RESPONSE_DELAY_MS: Int64 = 260
    static let HORSE_BOT_THINK_DELAY_MS: Int64 = 620
    static let QUESTION_CARD_WIDTH_PERCENT: Float = 0.90
    static let HORSE_END_CELEBRATION_MS: Int64 = 2800
    static let HEBREW_ANSWER_LABELS = ["\u{5D0}", "\u{5D1}", "\u{5D2}", "\u{5D3}"]
    static let HORSE_RECENT_QUESTION_MEMORY = 8
    static let BOT_COURT_SEED_SALT: Int64 = 0x424F54434F555254

    static func newInstance(
        config: TripleShotGameConfig
    ) -> TripleShotGameFragment {
        let fragment = TripleShotGameFragment()
        let arguments = ABundle()
        arguments.putString(
            ARG_NAME,
            config.playerName
        )
        arguments.putString(
            ARG_GAME_TYPE,
            config.gameType.name
        )
        arguments.putString(
            ARG_MODE,
            config.limitMode.name
        )
        arguments.putStringArrayList(
            ARG_CATEGORIES,
            config.selectedCategories.elements
                .kSortedBy { $0.ordinal }
                .map { $0.name }
        )
        arguments.putString(
            ARG_ROOM,
            config.roomId
        )
        arguments.putLong(
            ARG_ROOM_STARTED_AT,
            config.roomStartedAtMs
        )
        arguments.putBoolean(
            ARG_BOT_MATCH,
            config.botMatch
        )
        arguments.putString(
            ARG_PLAYER_CHARACTER,
            config.playerCharacterId
        )
        arguments.putString(
            ARG_BOT_CHARACTER,
            config.botCharacterId
        )
        arguments.putLong(
            ARG_SEED,
            config.seed
        )
        arguments.putInt(
            ARG_BALL_LIMIT,
            config.ballLimit
        )
        arguments.putInt(
            ARG_TIME_LIMIT_SECONDS,
            config.timeLimitSeconds
        )
        fragment.arguments = arguments
        return fragment
    }
}

// MARK: - Part 2 helpers (iOS)

/// Kotlin `MutableSet<String>.add(e)` / `clear()` on part 1's `seenLiveShotIds` (Kotlin `mutableSetOf`, used for
/// membership only): the same calls work whether part 1 holds it as a Swift `Set` or as a `KLinkedSet`.
private func game2SetAdd(_ set: inout Set<String>, _ element: String) -> Bool { return set.insert(element).inserted }
private func game2SetAdd(_ set: inout KLinkedSet<String>, _ element: String) -> Bool { return set.add(element) }
private func game2SetClear(_ set: inout Set<String>) { set.removeAll() }
private func game2SetClear(_ set: inout KLinkedSet<String>) { set.clear() }
