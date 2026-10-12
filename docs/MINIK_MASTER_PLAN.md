# MINIK — MASTER PRODUCT, ARCHITECTURE & DELIVERY PLAN

**Canonical handoff document for ChatGPT, Codex, and future development sessions**
**Snapshot date: 2026-08-31**
**Document status: v2 — canonical baseline plus the user-confirmed Ping Pong product decision and implementation sprint**
**Repository path:** `ios/docs/MINIK_MASTER_PLAN.md`

> **2026-10-12, owner decision.** The iOS math app this plan calls Minik Math is now **Minik Math Plus**
> (target `MinikMathPlus`, `com.appsbybros.minik.math.plus`), like its Android twin. **Minik Math** (target
> `MinikMath`, `com.appsbybros.minik.math`) is now Android Minik Math's web app in an iOS host:
> `docs/minik-math-ios.md`.

---

## 0. Why this document exists

This file is the single long-form source of truth for finishing Minik on iPhone/iPad. It exists so a new ChatGPT session, a new Codex session, or another engineer can understand the product without reconstructing months of conversation.

It intentionally contains four kinds of information:

1. **What the Android application actually is today** — because Android is the behavioral/content/product reference for the language product and for shared product systems.
2. **What the iOS products are supposed to become** — including Minik Math, which does **not** exist on Android and therefore must not be reverse-engineered from Android Math code that does not exist.
3. **What has already been implemented in iOS as of 2026-08-30** — including known limitations and branch/commit state.
4. **The complete execution plan to release** — architecture, sprints, Definition of Done, App Store work, ads, remove-ads, Firebase records, progress, parent area, localization, artwork, testing, TestFlight, and release.

### 0.1 Mandatory rule for future sessions

Before changing production code, a new ChatGPT/Codex session must read this document completely, then inspect the current repository state. It must **not** replace confirmed product requirements with guesses.

### 0.2 Protection rule for this file

Sections marked **CANONICAL PRODUCT CONTRACT** may only be changed when the user explicitly changes a product requirement or when a verified Android fact is corrected. Codex may update the **Living Status**, **Sprint Status**, **Decision Log**, and **Sprint Log** after each sprint without deleting the explanatory product sections.

### 0.3 Status vocabulary

- **VERIFIED ANDROID:** observed in the supplied Android snapshot/source/resources.
- **USER-CONFIRMED:** explicitly required by the product owner.
- **IMPLEMENTED iOS:** production code exists in the current iOS work.
- **STATICALLY REVIEWED:** code was independently inspected/parsed where possible, but not compiled in Xcode.
- **MAC VALIDATION PENDING:** requires Xcode/XCTest/Simulator on macOS.
- **OPEN PRODUCT DECISION:** must be answered by the user; Android cannot decide it.
- **RELEASE BLOCKER:** required before shipping.

---

# PART I — CANONICAL PRODUCT CONTRACT

## 1. Product model

### 1.1 The products

There are two educational product outcomes:

1. **Minik Language** — currently represented in iOS by the `MinikPlus` target/code name.
2. **Minik Math** — a separate math-learning product sharing the same engines, shell, design system, infrastructure, rewards, settings, parent area, commerce, and backend where appropriate.

There is also a language policy variant:

3. **Minik Plus English / English Only** — not a third architecture. It is the same Language product with policy differences: learned language fixed to English; no learned-language selector; Hebrew interface locale excluded while other supported interface locales remain available.

There is also a fourth, intentionally non-educational product:

4. **Minik Ping Pong** — a standalone Ping-Pong-only app using the same game engine and future shared monetization services, but no Language or Math curriculum.

Current XcodeGen configuration has four iOS targets:

- `MinikPlus`
- `MinikPlusEnglish`
- `MinikMath`
- `MinikPingPong`

The codebase must remain shared. Do not duplicate activity engines per product.

### 1.2 Platform authority

**USER-CONFIRMED:**

- Android is the behavioral/content/product reference for **Language** and for shared Minik systems that already exist there.
- Android contains **no Math product**. Do not search Android for a Math curriculum or assume Android defines Math activity behavior.
- Minik Math is intentionally freer: reuse the proven activity families and child-friendly Minik identity, but define mathematical content cleanly and systematically for iOS.
- Native Apple conventions take precedence over Android presentation only when they improve iPhone/iPad layout, accessibility, navigation, lifecycle, safe areas, controls, gestures, Dynamic Type, or RTL without changing the educational/product contract.
- `ios/docs/android-known-fixes.md` overrides known Android snapshot bugs.

### 1.3 Fundamental Math rule

**USER-CONFIRMED, NON-NEGOTIABLE:**

> **Level = WHAT the child is learning. Activity = HOW the child practices it.**

A Math activity must not silently fall back to an easier level's content just because that activity engine is easier to implement.

Example:

- A Level 1 visual-choice activity may show five strawberries and ask for `5`.
- The same activity at a higher level may show `30 ÷ 6` and ask for `5`.
- Soccer remains Soccer; Tower remains Tower. The educational content inside them changes with the level.

### 1.4 Ping-Pong-only product contract

**USER-CONFIRMED 2026-08-31:**

- `ProductVariant.minikPingPong`, Xcode target/product `MinikPingPong`, and compilation condition `MINIK_PING_PONG` define the fourth product.
- It launches directly into a minimal Ping Pong shell rather than an educational activity hub.
- It contains Ping Pong gameplay, score, win/loss result, difficulty, applicable control-mode selection, and match-target selection.
- It contains no Language curriculum, Math curriculum, learned-language state, Parent Area, or educational activity hub.
- Future Remove Ads, “I have a code,” and interstitial behavior must use the shared app-level Ads/commerce/code systems. The game may only report completed-match opportunities; it must never implement or fake its own purchase, entitlement, ad, or redemption success.
- Interstitial opportunities are allowed only between completed matches, never during serve, rally, or point resolution. Cadence is configurable; the provisional cadence is every two completed matches, and a future Remove Ads entitlement suppresses them.

---

## 2. What the Android application actually contains

The supplied Android snapshot includes, among others:

- `MainActivity.kt`
- `IntroScreen.kt`
- `ButtonsMenuFragment.kt`
- `LanguagesAndLevelsDialogFragment.kt`
- `LearnScreen.kt`
- `LetterPairsFragment.kt`
- `WriteScreen.kt`
- `RandomWordCardsFragment.kt`
- `LettersSoccerGame.kt`
- `LettersTowerFragment.kt`
- `MemoryGameFragment.kt`
- `TicTacToeFragment.kt`
- `StatisticsDialog.kt`
- `RecordsLeaderboardDialogFragment.kt`
- `RemoveAdsReminderFragment.kt`
- `InterstitialHelper.kt`
- `SharedPreferencesCache.kt`
- `TextToSpeechManager.kt`
- `UserLanguageManager.kt`
- `ConfettiRectView.kt`
- corresponding phone/tablet layouts and localized strings.

This is a full child-facing product, not a collection of isolated exercise sessions.

The companion [Android UI reference index](reference/android-ui/README.md) describes 16 repository screenshots covering representative Language activities, games, menus, mascot/feedback presentation, navigation, scores/records, and Parent Area. The owner's 2026-09-06 gate makes every image a binding Language/shared visual reference together with Android layout/source/assets; all known source discrepancies must be addressed before source-parity completion.

### 2.1 Android home/product shell

**VERIFIED ANDROID + USER-CONFIRMED screenshots:**

The Plus product has a colorful Minik shell with:

- Minik/MinikPlus branding and mascot artwork.
- Home navigation.
- Trophy/records/high-score access.
- Points and record/streak display.
- Sectioned activity cards.
- Language/level/settings access.
- Parent/settings area.
- Advertising/removal entry points when applicable.
- Child-friendly success/failure presentation and mascot reactions.

The iOS product must provide the same product breadth with a native SwiftUI implementation rather than reproducing Android XML literally.

### 2.2 The 13 Android-visible Language production activities

**USER-CONFIRMED canonical inventory:**

1. **Letters Review / Learn Letters** — instructional; letter/examples/images and speech.
2. **Letter Pairs** — 8 pictures / 4 pairs; pair pictured words sharing the same starting letter; tapping speaks; correct pair disappears/scores.
3. **First Letter — picture → letter** — image then choose the first letter.
4. **First Letter reverse — letter → picture** — letter then choose the image whose word starts with it.
5. **Picture → Word** — image plus four learned-word answers.
6. **Word → Picture** — learned word plus four image answers.
7. **Build Word** — construct the word; correctness follows ordered construction rules.
8. **Mixed** — cycles multiple exercise types according to the production cadence/capability policy.
9. **Word Cards / Flash Cards** — learned words presented sequentially with speech, shuffle/manual/timed behavior, looping.
10. **Soccer** — word construction through soccer actions; educational correctness and shot outcome are separate.
11. **Tower / Alphabet Blocks** — build a word from ordered letter blocks into a tower.
12. **Pictures Memory** — picture ↔ identical picture; revealing a card speaks the learned word.
13. **Tic-Tac-Toe** — just for fun; not a language exercise.

Generic helper engines such as generic Choose/Build/Pairs/Memory may exist internally, but they do **not** count as additional production activities.

### 2.3 Confirmed detailed Android mechanics already migrated/reviewed

#### Picture Memory

- Two physical picture cards share the same semantic content identity.
- It is picture↔picture, not picture↔word.
- Revealing a picture speaks the represented learned-language word.
- Correct matching is semantic, not physical-card identity.
- Math Memory remains silent unless Math explicitly defines narration.

#### Mixed

Normal production cadence already established:

- 20 Word → Picture
- 10 Picture → Word
- 5 Word Build
- repeat

The iOS migration counts real challenge advances rather than reproducing Android counter quirks.

#### Language Soccer

Confirmed contract:

- The educational action is choosing/kicking the next correct letter of the target word.
- Correct letter advances the word even if the shot misses/is saved.
- Wrong letter never advances/consumes.
- Duplicate letters are distinct physical balls but semantically interchangeable when the token matches.
- Score matrix:
  - correct + goal → child +1
  - correct + miss/saved → nobody
  - wrong + goal → nobody
  - wrong + miss/saved → keeper +1
- Continuous practice across words.
- Target word spoken at round start; kicked letter spoken using correct pronunciation metadata, including Hebrew final forms.
- Math Soccer follows the same score matrix, but its educational content is numeric/math rather than letters.

#### Language Tower

Confirmed Android behavior:

- First letter is locked as the base.
- Remaining letters are draggable.
- Only the next expected semantic letter is accepted.
- Wrong near-target placement gives failure feedback but does not consume/advance.
- Whitespace is not draggable and is inserted automatically in the built display.
- Correct letter is spoken; completed word is spoken.
- Continuous next-word practice for the relevant Plus path.

#### Tic-Tac-Toe

Confirmed Android production behavior:

- Standard 3×3 board; 8 winning lines; full no-winner board = draw.
- Child starts every round whether choosing X or O.
- Mark choice locks after the first move and unlocks next round while retaining selection.
- A/B/C/D/E/Random/Adaptive difficulty behavior exists.
- Easy random empty; Medium uses prioritized win/block/center/corner/edge with level probabilities; Hard is minimax and unbeatable.
- Plus Games path loops rounds until explicit exit; hidden cumulative score is retained internally.
- Result messages, speech, animations, confetti/timing and intro gating exist.
- Human moves use one of two kick sounds; AI move silent.
- Android has a live Random/Adaptive DDA mismatch; iOS isolates that behind a compatibility policy rather than spreading it through the game.

### 2.4 Audio and speech

**VERIFIED ANDROID + USER-CONFIRMED:**

- Android uses TTS extensively.
- Some activities speak an instructional/target item on entry or when a new round begins.
- Many screens have an explicit speaker/replay button.
- Correct letter/word speech can be part of the interaction.
- Hosting/interface language and learned language are different concerns.
- iOS must preserve this separation. Learned vocabulary speech must not be tied to the UI locale, and UI/game feedback must not misuse the learned-language TTS service.

### 2.5 Success/failure feedback, Minik, points and streaks

**VERIFIED ANDROID + USER-CONFIRMED screenshots:**

The product includes more than correct/incorrect text:

- Minik mascot reactions/poses.
- Success animations.
- Confetti in appropriate contexts.
- Positive spoken phrases.
- Failure/encouragement feedback.
- Points.
- Current streak / record streak concepts.
- Record/high-score presentation.
- Level-up/achievement-style feedback.

The iOS architecture must emit shared activity-result/reward events so every activity participates consistently instead of reimplementing scoring/rewards ad hoc.

### 2.6 Progress and statistics

**VERIFIED ANDROID:**

Android includes a `StatisticsDialog`, saved user state in shared preferences, points, level/ramp state, activity performance data, and records UI. The exact Android persistence schema is not automatically the desired iOS schema, but the user-facing capabilities must be accounted for.

Required iOS outcome:

- local durable progress state;
- per-product/per-profile curriculum progress;
- activity attempts/correctness;
- practice time where appropriate;
- points/streak/records;
- parent-readable progress summary;
- backend sync for the records features that are meant to be shared/global.

### 2.7 Records / leaderboard / Firebase

**VERIFIED ANDROID + USER-CONFIRMED:**

Android initializes Firebase/App Check and has a records/leaderboard dialog with score/streak categories. The product owner explicitly requires records/high scores to be preserved with Firebase-backed behavior.

Required iOS architecture:

- backend interface owned by the app layer, not by activity sessions;
- Firebase implementation for Minik records/leaderboards and any confirmed sync data;
- local cache/offline-safe behavior;
- child/privacy-safe identity model;
- App Check where supported/required by the backend;
- no activity directly calling Firebase.

Do not assume every Android Firebase analytics event must be copied blindly. Analytics/privacy policy must be reviewed under current Apple child-app rules before release.

### 2.8 Parent Area / settings

**USER-CONFIRMED + VERIFIED ANDROID layouts/source:**

The iOS Parent Area must ultimately include the relevant equivalents of:

- learned language selection for Minik Language;
- no learned-language choice in English Only (English fixed);
- app/interface language selection;
- reading/skill/level controls where applicable;
- Math level controls;
- encouragement/reminder toggle(s);
- progress/statistics view;
- points/high score/streak/records access;
- remove-ads purchase/restore controls;
- other adult-only links/actions behind an appropriate parental gate if the App Store child category requires it.

### 2.9 Ads and Remove Ads

**VERIFIED ANDROID + USER-CONFIRMED:**

Android contains:

- interstitial ad flow;
- ad counters/skip logic;
- remove-ads purchase entry;
- remove-ads reminder UI;
- layout behavior that changes when ads are present/removed.

Required iOS outcome:

- provider boundary around ads;
- clearly defined display policy/events rather than ad calls inside activity code;
- purchase entitlement removes ads immediately and persistently;
- restore purchases;
- reminder cadence/state;
- no child-targeted/behavioral advertising if prohibited by the selected App Store category/policy;
- parental gating for purchasing/external links where required.

**APPLE POLICY CHECKPOINT (verified 2026-08-30 against Apple documentation):** if Minik is submitted in the Kids Category, purchasing opportunities/links must be reserved for a designated parental area/gate, third-party analytics/ads are heavily restricted, and contextual ads are only permitted in limited policy-compliant cases. This must be re-verified immediately before release because App Review rules can change.

### 2.10 Notifications / encouragement

**USER-CONFIRMED REQUIRED iOS FEATURE:**

The final app includes encouragement/reminder notifications, controlled by user/parent settings. The design must include:

- permission request at an appropriate adult-controlled point, not on blind first launch;
- local notification scheduling/cancellation;
- cadence rules;
- localization;
- product-aware copy;
- no sensitive progress content on lock screen by default;
- setting persistence.

### 2.11 Android localization inventory

Current verified interface-language inventory from Android main app resources:

- English
- Amharic
- Arabic
- German
- Spanish
- French
- Hebrew
- Dutch
- Portuguese (Brazil)
- Portuguese (Portugal)
- Russian

Important distinctions:

- interface locale != learned language;
- Hebrew/Arabic UI are RTL;
- learned content direction is independent;
- English Only fixes **learned language** to English, excludes Hebrew as an interface choice, but retains the other supported interface locales;
- partial translations existing only in Android support libraries do not automatically become supported Minik interface locales.

### 2.12 Android reading/hosting-language policy

Android has reading-skill/hosting-language behavior that affects some clues/content choices. iOS has not yet modeled the full capability/parent-policy layer. This is a known parity area and must be addressed before Language release sign-off rather than accidentally hard-coding current Level A behavior forever.

---

# PART II — CANONICAL iOS PRODUCT TARGET

## 3. iOS architecture — required end state

### 3.1 Layering

The final architecture should be organized around these responsibilities:

1. **Product Configuration** — target/policy: Language, English Only, Math, Ping-Pong-only.
2. **Curriculum** — WHAT content is available at each language/math level.
3. **Activity Definitions** — HOW the child practices; production activity identity separate from generic engine type.
4. **Content Providers / Round Generators** — create semantic prompts, answers, distractors and representations.
5. **Pure Sessions / Game Engines** — deterministic state transitions and correctness.
6. **SwiftUI Activity Views** — presentation, gestures, animation, VoiceOver, lifecycle.
7. **Shared Feedback/Reward Layer** — points, streaks, success/failure, Minik, confetti, speech events.
8. **Progress Store** — local durable progress/statistics.
9. **Backend Services** — Firebase records/sync behind protocols.
10. **Parent & Settings** — adult controls, progress, languages, levels, notifications, purchases.
11. **Ads Boundary** — no SDK coupling in activity engines.
12. **Commerce Package** — reusable StoreKit package independent of Minik.
13. **Localization** — String Catalogs and locale policy.
14. **Assets/Artwork** — vocabulary images, math object library, mascot states, app icons.
15. **App Shell** — Home, activity menu, records, parent area, navigation.

### 3.2 Production activity identity must be explicit

A production activity is not the same thing as a reusable engine.

Example:

- `MultipleChoiceSession` may power Picture→Word, Word→Picture, First Letter, Math Visual→Answer, and Math Answer→Representation.
- Those remain distinct product activities because their semantics, prompts, menu placement, speech, progress metrics, and curriculum contracts differ.

### 3.3 Event-driven shared services

Every activity should emit typed events such as:

- activity started;
- challenge presented;
- answer attempted;
- correct/incorrect;
- round completed;
- activity completed/continued;
- score changed;
- streak changed;
- reward earned.

Shared services consume these events for progress, points, records, ads scheduling and feedback. Activities must not directly know Firebase/StoreKit/ad SDK APIs.

---

## 4. Language product — release target

### 4.1 Language production menu contract

Exactly the 13 production activities listed in §2.2 should be exposed. Internal helper engines remain hidden.

### 4.2 Deep parity requirement

A route/factory test alone does not equal release parity. Every activity must eventually pass a deep audit covering:

- Android behavior and known fixes;
- target learned-language policy;
- hosting/UI language policy;
- speech timing and replay buttons;
- progression and retry behavior;
- score/points/progress events;
- success/failure animation;
- iPhone/iPad layout;
- Dynamic Type;
- VoiceOver;
- RTL/LTR independence;
- lifecycle cancellation;
- final artwork/assets;
- localization;
- macOS/Xcode tests.

---

# PART III — MINIK MATH CANONICAL PRODUCT DESIGN

## 5. Math has 13 production activities too

**USER-CONFIRMED:** Math should carry the richness of the Language product rather than collapse into seven generic engines. The two Language activities that exist only because of “first letter” semantics are replaced by two simple Math construction activities.

### 5.1 Canonical Math activity set

| # | Math production activity | Language counterpart | Core Math behavior |
|---|---|---|---|
| 1 | **Learn Math** | Learn Letters | Instructional, not a test. Show a concept and its answer/relationship. Example M1: 3 strawberries + `3`; later: `5 × 8` + `40`. |
| 2 | **Math Pairs** | Letter Pairs | Match two equivalent/related mathematical representations. M1: numeral ↔ quantity; later: expression ↔ equivalent value/expression. |
| 3 | **Build Number** | First Letter picture→letter replacement | Simple construction of the numeral/answer from a quantity or other approved prompt. Must remain distinct from the full Build Math activity. |
| 4 | **Build Quantity** | First Letter letter→picture replacement | Simple construction of the requested quantity/representation from a numeral/approved prompt. Distinct from Build Number and Build Math. |
| 5 | **Visual → Answer** | Picture→Word | Show a visual/math prompt, then four textual/numeric answers. Correct answer appears exactly once; distractors are plausible. |
| 6 | **Answer → Representation** | Word→Picture | Show a target number/value, then four visual/math representations; exactly one is semantically correct. |
| 7 | **Build Math** | Build Word | Full ordered answer/expression construction using tokens/input appropriate to the level. This is not automatically identical to Build Number. |
| 8 | **Math Mixed** | Mixed | Cycles several approved activity modes appropriate to the current Math level. |
| 9 | **Math Cards / Facts Table** | Word Cards | Learning/review sequence such as addition table or multiplication table; active cell/fact changes over time/manual advance. |
| 10 | **Math Soccer** | Soccer | Fixed answer-ball pool for a round; question changes until balls are consumed. Educational correctness is separate from shot outcome. |
| 11 | **Math Tower** | Tower | Build the target amount/value by dragging blocks; content adapts by level. |
| 12 | **Math Memory** | Picture Memory | Match two semantically equal mathematical representations. |
| 13 | **Ping Pong** | Ping Pong / Table Tennis | Just for fun; intentionally non-educational and outside Math curriculum/providers. |

This 13-item list supersedes the mistaken idea that `MathActivityKind` having seven generic cases means the Math product has seven activities.

## 6. Math visual representation philosophy

### 6.1 Beautiful object library, not dots as the final product

**USER-CONFIRMED:** final Math quantity prompts should use polished child-friendly art such as:

- strawberries;
- apples;
- bananas;
- chocolates;
- balls;
- other colorful/whimsical objects.

A single object asset is repeated/layout-composed dynamically; do not create a separate image asset for every quantity.

Dots may be used only as temporary development placeholders, never as the final visual identity unless the user explicitly chooses them for a specific teaching representation.

### 6.2 Scaling quantities

The representation system must avoid absurd layouts such as 108 individual objects.

Required strategy:

- small values: individual objects;
- larger values: structured grouping appropriate to the curriculum (for example groups/tens/ones/arrays/number-line/bundles);
- higher levels: operations and symbolic representations replace raw counting where pedagogically appropriate.

Exact thresholds are curriculum decisions and will be documented per level rather than hard-coded globally without approval.

### 6.3 Distractor quality

**USER-CONFIRMED:** four-choice exercises must not use obviously random answers.

Rules:

- correct answer appears **exactly once**;
- all options are distinct unless the specific mechanic explicitly permits duplicate physical answers (Soccer may);
- distractors should be plausible and level-aware;
- examples: adjacent count error, operand confusion, nearby value, wrong tens/ones, common arithmetic mistake, inverse-operation result, off-by-one, result from a visually similar prompt;
- generator must guarantee enough valid distractors and deterministic testing.

## 7. Detailed Math activity contracts

### 7.1 Learn Math

Instructional only. It teaches the relation instead of asking for an answer.

Examples:

- M1: three strawberries displayed with `3`.
- multiplication level: `5 × 8` displayed with `40`.
- fraction level: representation + fraction/decimal equivalence as approved.

Needs optional speech/instruction replay where appropriate, pacing/manual advance, and table/review modes where the curriculum calls for them.

### 7.2 Math Pairs

Pairs are semantic, not visual duplication.

Examples:

- `5` ↔ five strawberries;
- `2 + 3` ↔ `5`;
- `3 × 4` ↔ `12`;
- fraction/decimal equivalents at later levels.

### 7.3 Build Number

Simple Math replacement for one first-letter activity. The purpose is direct construction of the target numeral/answer, not word spelling.

At M1 the prompt is a quantity in `0...10`; several draggable numeral tokens are offered and the correct numeral occurs exactly once. No iOS keyboard is used. Later multi-digit answers are constructed digit by digit with distinct physical token IDs, including repeated digits, and future signed/decimal answers may add `-` and `.` tokens. It remains deliberately simpler than full Build Math.

### 7.4 Build Quantity

At M1, show a numeral in `0...10` and let the child drag/add exactly that many child-friendly objects into a target. Explicit submit validates semantic count, and remove/undo makes overshoot recoverable. Zero means adding nothing and submitting. Later representations evolve to grouping, place value, equal groups, fractions, or lines rather than absurd individual-object counts.

### 7.5 Visual → Answer

Canonical early-level example:

- prompt: five strawberries;
- answer choices: `2`, `4`, `5`, `15` (example only; distractor generator owns final choices);
- `5` must appear exactly once.

Higher-level example:

- prompt: `30 ÷ 6`;
- choices include `5` and plausible wrong answers.

### 7.6 Answer → Representation

Canonical early-level example:

- target: `5`;
- four visual choices: quantities such as 3, 5, 8, 15 using the object-layout system.

Higher-level example for target `5`:

- `2 + 4`
- `8 - 3` ← correct
- `9 - 3`
- `3 + 3`

The actual expressions depend on level content.

### 7.7 Build Math

Full construction counterpart of Build Word. Depending on level it can construct:

- a numeral;
- an equation;
- a missing value;
- an ordered mathematical expression;
- another approved structured answer.

**USER-CONFIRMED:** M1 Build Math is **Build the Count**. For a nonzero target quantity `N`, the child constructs the ordered chain `1 → 2 → ... → N` from number tokens, with extra candidate tokens and distinct physical IDs. This reinforces counting order and cardinality and is intentionally different from selecting numeral `N` in Build Number or constructing `N` objects in Build Quantity.

### 7.8 Math Mixed

A level-specific cycle over centrally approved graded educational modes. It never injects Learn, instructional Cards, or Ping Pong, delegates the real child-mode result to progress/adaptation, and avoids immediate pathological repetition. Exact cadence remains tunable policy data.

### 7.9 Math Cards / Facts Table

A learning/review activity rather than a graded one-question game. It supports useful manual, shuffle, and timed/looping review where appropriate and does not directly affect automatic level while instructional.

Examples:

- addition table;
- multiplication table;
- one fact/cell highlighted at a time;
- progresses manually or on a controlled timed mode;
- loops/reviews according to curriculum.

### 7.10 Math Soccer

**USER-CONFIRMED:**

- A round has a fixed pool of soccer balls carrying answer values.
- Questions change; balls do not get regenerated after each question.
- Correct ball is determined semantically for the current question.
- It is allowed to have two physical balls with the same displayed number when they correspond to separate questions/uses.
- Continue until the answer-ball pool is consumed according to the round design.
- Example M1: five strawberries → kick ball `5`.
- Higher level: `30 ÷ 6` → kick ball `5`.
- Score matrix remains the confirmed Soccer matrix:
  - correct + goal: child +1
  - correct + miss/save: nobody
  - wrong + goal: nobody
  - wrong + miss/save: keeper +1

### 7.11 Math Tower

**USER-CONFIRMED:** this is never number sorting and has two caller-selected modes.

- **Count Tower** for small readable answers: show the numeral/expression target, provide more blocks than the answer requires, let the child add/remove blocks, and validate only through an explicit large turquoise/silver checkmark buzzer. There is no countdown or inactivity completion. M1 shows the numeral `0...10`, not object pictures; zero blocks plus submit is valid. Wrong submit leaves the construction editable.
- **Answer Token Tower** for larger answers: build the ordered answer using digit/sign/decimal/fraction tokens as approved. For `10^4 → 10000`, build `1 → 0 → 0 → 0 → 0`. Repeated visible digits have distinct physical IDs and extra candidate tokens are always present.

The provider/caller chooses the mode from the approved readable representation; there is no hard global level threshold. Existing Language Tower ordered-letter behavior and speaker/replay behavior must be preserved. Math Tower uses interface/hosting-language prompt speech.

### 7.12 Math Memory

Match two equivalent values/representations. Examples vary by level: quantity↔numeral, expression↔value, equivalent expressions, fractions/decimals, etc. It must obey the current level's WHAT.

### 7.13 Ping Pong / Table Tennis

**USER-CONFIRMED 2026-08-31:** Language keeps Tic-Tac-Toe as its just-for-fun game. Minik Math uses Ping Pong. Ping Pong is not a `MathActivityKind`, `MathContentProvider`, challenge, skill, or learned-language activity.

#### 7.13.1 Four difficulties and controls

- **Starter** is a deliberately simplified drag-to-ball introduction. Minik automatically feeds slow balls; the child moves the approved middle paddle inside the lower strike region and receives a strongly assisted legal return when paddle and ball overlap.
- **Easy**, **Medium**, and **Hard** use the full timing/placement game. Before every new match the child chooses **Tap** or **Swipe**. Difficulty and the most recent full-game control mode persist independently.
- Switching to Starter hides the Tap/Swipe selector; switching away restores the persisted choice. Settings apply to the next match, not halfway through a rally.
- Easy has generous spatial/timing assistance. Medium is a meaningful challenge. Hard is faster and tighter but always retains non-zero Minik error and must remain beatable.

#### 7.13.2 Table and legal strike geometry

The game is top-down portrait table tennis: child at the bottom, Minik at the top, net at center. Ordinary child contact is legal only from the bottom baseline to approximately halfway between the bottom baseline and the net. A dragged paddle outside that region fades/becomes logically inactive and reactivates on re-entry. There are no Pong side-wall bounces.

#### 7.13.3 Tap

Tap means the child taps where the paddle should swing; the paddle is not persistently dragged. A return succeeds only after a legal bounce and when both timing and spatial distance are within the current difficulty tolerance. Left-half contact uses the current difficulty's backhand artwork; center/right uses forehand. Tap/contact offset modestly changes outgoing horizontal direction. Marginal timing/position lowers shot quality and can produce a net or out; there is no power meter.

#### 7.13.4 Swipe and Starter drag

Swipe is a physically controlled logical paddle that follows a held finger inside the legal strike zone. Crossing to the left selects backhand artwork; center/right selects forehand. The child may keep the finger down between returns. Collision uses legal rally state, paddle position, velocity, direction, and timing. Velocity affects power and direction, with centralized safe clamps preventing tunneling, degenerate angles, or one noisy sample creating an absurd shot. Starter uses the same zone but the dedicated middle-paddle asset and assisted overlap contact rather than full Swipe power/aim.

#### 7.13.5 Shared contact and flight model

Tap and Swipe produce one `PingPongContact` containing point, timing quality, spatial quality, paddle velocity, intended horizontal direction, and mode. One shared solver creates outgoing velocity/arc. Ball flight is deterministic manual logic: normalized x/y, simple height/gravity, table bounce, net crossing/height, and out detection. A normal shot must clear the net and first-bounce on the opponent side. Net, first-bounce out, second bounce/no return, or leaving the table resolves the rally; no invisible wall recovery or service lets are implemented. Real spin, 3D, and tournament-level foul complexity are intentionally out of scope.

#### 7.13.6 Serving

- Starter always receives an automatic Minik feed and has no manual legal serve ritual.
- Tap serve accepts a tap anywhere on the table. A tap on the child half primarily supplies the own-side first bounce; a tap on the Minik half primarily supplies the receiver-side second bounce. The solver derives the other bounce and applies difficulty-based assistance.
- Swipe serve presents a ready ball on the child side and uses swipe speed, direction, and contact placement. It must still bounce on the server side, clear the net, and bounce on the receiver side; an illegal child serve awards Minik the point.
- Minik serves automatically after a short visible ready/strike transition, with difficulty-dependent speed, placement, side preference, and non-zero error.

#### 7.13.7 Minik rally AI

Minik return success is not a blind coin flip. It combines predicted landing/contact position, incoming speed/angle/depth, reaction delay, reach, prediction, tracking/aim error, and a small difficulty-dependent random error. Slow central shots are easier; fast/deep/corner shots are harder. Reached shots use the corresponding ready/strike pose pair. Hard is strong but never perfect.

#### 7.13.8 Match targets, scoring, and service rotation

- Starter/Easy targets: `3 / 5 / 7 / 10`, default `7`; first to target wins with no two-point requirement.
- Medium/Hard targets: `3 / 5 / 7 / 11`, default `7`; target plus a two-point lead is required, with no score cap.
- Starter: Minik feeds every rally. Easy: child serves every rally.
- Medium/Hard: child starts; service rotates in groups of two completed rallies. Once both reach `target - 1`, service alternates every rally.
- Play Again resets score/service state while preserving difficulty, applicable control mode, and the per-difficulty target.

#### 7.13.9 Presentation, accessibility, and lifecycle

The dedicated arena is used instead of the generic practice frame. SpriteKit is embedded in SwiftUI, while scoring, flight, contact, AI, persistence validation, and service rules remain pure/testable. The HUD shows scores, current settings, target, and useful server state without covering the table. Score/server/result announcements and left/right accessibility actions provide a practical alternative for the timing/spatial game. Reduce Motion keeps required ball motion but reduces pose flourishes. Backgrounding, disappearance, and exit pause/cancel simulation and pending work so a point cannot duplicate after resume.

#### 7.13.10 Approved production artwork

Production asset names are:

- `ping_pong_arena`, `ping_pong_table`, `ping_pong_ball`;
- `ping_pong_player_starter_paddle`;
- `ping_pong_player_easy_backhand`, `ping_pong_player_easy_forehand`;
- `ping_pong_player_medium_backhand`, `ping_pong_player_medium_forehand`;
- `ping_pong_player_hard_backhand`, `ping_pong_player_hard_forehand`;
- `minik_ping_pong_left_ready`, `minik_ping_pong_left_strike`;
- `minik_ping_pong_right_ready`, `minik_ping_pong_right_strike`.

The staging typo `strater` and generated `ChatGPT Image ...` filenames must never leak into production API/user-facing names. The selected ball is the visually inspected first square white-ball candidate (`ChatGPT Image Aug 31, 2026, 01_23_08 AM (2).png` in staging). Artwork is presentation only; hit/collision decisions remain data-driven.

---

## 8. Math curriculum M1–M10 — confirmed progression

The following WHAT progression is user-confirmed. All twelve educational activity identities remain present at every level and evolve their HOW; Ping Pong remains the thirteenth non-curriculum identity. Exact generated pools and cadence remain tunable engineering policy without reopening these curriculum decisions.

The durable 130-cell architecture/status inventory is maintained in [`math-production-matrix.md`](math-production-matrix.md). It separates user-confirmed product authority from implementation status and records the remaining higher-level content-authoring/tuning work without treating identity or route presence as completion.

### M1 — Number represents quantity

`0...10`: counting, cardinality, numeral↔quantity, and basic more/less where useful.

Expected visual emphasis: beautiful individual-object quantities.

### M2 — Composition/decomposition and early operations

Values/results within `0...10`: part/whole, early addition/subtraction, and complements to ten.

### M3 — Operations and relationships between expressions

Addition/subtraction relationships within `0...20`: missing values/addends, equivalent expressions, and relationships among expressions.

### M4 — Place value / numbers to 100 / richer addition-subtraction

Numbers to 100: place value, tens/ones, comparison/magnitude, and richer addition/subtraction within 100.

### M5 — Meaning of multiplication and division

Equal groups, arrays, sharing/grouping, and simple multiplication/division facts, especially the 1–5 and 10 families.

### M6 — Fluency, factors/multiples, initial fraction relationships

Multiplication/division fluency through `10×10` and corresponding division, factors, multiples, and initial half/quarter/simple-fraction relationships.

### M7 — Fractions and decimals as numbers

Simple fractions and tenths/hundredths as numbers: magnitude, comparison/order, number line, and basic equivalence.

### M8 — Fraction / decimal / percent / ratio relationships

Translation among fraction/decimal/percent/ratio forms, simple ratios, and semantic equivalence such as `1/2 = 0.5 = 50%`.

### M9 — Pre-algebra

Negative numbers, basic order of operations, simple powers, ratios, and one-step equations.

### M10 — Algebraic relationships

One/two-step equations, simple linear relationships, proportional reasoning, and introductory probability/geometry concepts.

**Rule:** none of these levels becomes implementation-ready merely because an enum/descriptor exists. Automatic routing is clamped to the highest level whose twelve educational activities are functionally runnable. All thirteen identities remain in the architecture/menu contract; unfinished content is never substituted with an unrelated engine.

---

# PART IV — ENGLISH ONLY CONTRACT

## 9. Minik Plus English / English Only

The English Only target uses the shared Language architecture.

Required behavior:

- learned language is always English;
- learned-language selector hidden/unavailable;
- stored unsupported/Hebrew learned-language values resolve to English;
- Hebrew is excluded from interface-language choices;
- the other verified Android interface locales remain eligible;
- all 13 Language production activities remain available unless a separately documented product policy says otherwise;
- no forked copies of activity engines;
- same parent/progress/rewards/ads/commerce infrastructure;
- separate App Store bundle/listing only if that remains the chosen distribution model.

Final release gate must test English Only independently from MinikPlus because policy bugs can compile successfully while exposing the wrong language choices.

---

# PART V — SHARED SYSTEMS REQUIRED FOR A COMPLETE APP

## 10. App shell and navigation

Final SwiftUI shell must include:

- branded home/menu;
- sectioned activity cards;
- Home affordance;
- points/streak/records affordance;
- Parent Area entry;
- settings/language/level entry where relevant;
- navigation/presentation that works on small iPhone, large iPhone and iPad;
- safe-area correctness;
- portrait/landscape behavior according to final product policy;
- no activity owning global navigation state.

## 11. Rewards, points, streaks, achievements and records

Create a shared typed reward system:

- points rules;
- current streak;
- best streak;
- high score / record categories;
- activity result summaries;
- level-up/achievement events if retained;
- persistence;
- backend upload/download for global records where required;
- no duplicated per-view scoring logic.

## 12. Progress model

Required data model should support:

- product/profile identity;
- current Language content level / reading skill where applicable;
- Math level;
- per-activity attempts/correct/incorrect;
- per-skill mastery/progress;
- practice time/session history where approved;
- most recent activity date;
- points/streak records;
- parent-readable aggregates;
- migration/versioning of local storage.

Use protocols so storage can start local and sync selected data via Firebase without coupling activities to Firebase.

### 12.1 Attempt identity and replay safety

Activity events carry unique event IDs and typed graded-attempt data: stable item/challenge identity where available, attempt index/first-attempt state, correct/incorrect/skip result, response duration, activity family, optional Math level, and optional skill. Correctness never depends on UI text. Applying the same event ID twice must be idempotent so future backend retry/sync cannot double-count; a genuine retry has a new event ID and attempt index.

### 12.2 Automatic Math level

Math defaults to **Automatic**. The child-facing hub shows the persisted active level but is not a free level picker. Future Parent Area exposes Automatic/Manual: Automatic prevents direct parent level selection; Manual allows Level 1–10 and never changes it automatically. Returning from Manual to Automatic uses the selected manual level as the new starting point.

Automatic tuning is centralized and testable:

- first run begins at Level 1 absent valid persisted state;
- calibration uses about three graded first attempts: `3/3` may test `+2`, `2/3` may test `+1`, and `0–1/3` settles/steps down;
- normal promotion: eight consecutive first-attempt correct or at least 18 of the last 20;
- normal demotion: seven consecutive first-attempt unsuccessful or at most 8 of the last 20;
- time is a secondary activity-family baseline; one response over roughly two minutes is a signal, never sole demotion authority;
- an increase has about six graded probation attempts and reverts near four failures; ordinary changes then have about ten attempts of cooldown, with severe failure allowed to override;
- eligible graded families are Pairs, Build Number, Build Quantity, Visual→Answer, Answer→Representation, Build Math, graded Mixed child modes, Soccer, Tower, and Memory;
- Learn, instructional Cards, and Ping Pong do not directly affect level;
- routing is clamped to the highest implementation-ready level (currently M10); all ten canonical levels are eligible because each full twelve-activity production slice is coherent.

## 13. Parent Area

Final Parent Area should expose appropriate adult controls and information in one coherent place:

- child/profile identity if the product supports multiple profiles;
- learned language (Language only);
- interface language;
- Language reading/skill/level controls;
- Math level controls;
- progress/statistics;
- points/streak/records;
- encouragement notifications setting;
- remove ads purchase/restore/status;
- privacy/support/legal links;
- version/build info if useful;
- parental gate for adult actions when required by App Store policy.

## 14. Firebase / backend architecture

Create an app-owned service boundary, for example:

- `RecordsRepository`
- `ProgressSyncRepository` if progress sync is approved
- `BackendIdentityProvider`

Firebase implementation belongs behind those protocols.

Required release work:

- iOS Firebase configuration per App Store target/environment;
- App Check configuration;
- Firestore/database contract compatibility where Android records must interoperate;
- offline cache/retry;
- duplicate/conflict handling;
- test/dev backend isolation;
- privacy review.

Do not embed Firebase types inside activity sessions.

## 15. Ads architecture

Create `AdService`/provider boundary with events such as “eligible interstitial opportunity”.

Requirements:

- no targeted advertising to children;
- App Store/Kids policy verified before choosing SDK/provider;
- interstitial frequency/counters documented and tested;
- clear ad labeling/close behavior;
- inappropriate-ad reporting if required by Apple/provider policy;
- disabled when remove-ads entitlement is active;
- no ads inside extensions/notifications;
- development/mock provider for tests.

## 16. Reusable Apple Store / StoreKit library

**USER-CONFIRMED:** App Store purchasing must be implemented in a **separate reusable library** that can be used in other applications.

### 16.1 Recommended package boundary

Create a standalone Swift Package, preferably in its own reusable repository or an easily extractable directory such as:

`Packages/AppStoreCommerceKit/`

The package must contain **no Minik-specific product IDs, strings, views, Firebase code, ad SDK code, or bundle assumptions**.

### 16.2 Generic package responsibilities

Suggested public concepts:

- `CommerceProductID`
- `CommerceProduct`
- `EntitlementID`
- `EntitlementState`
- `PurchaseOutcome`
- `CommerceStore` protocol
- `StoreKitCommerceStore` implementation
- product loading;
- purchase flow;
- verified transaction handling;
- current entitlement refresh;
- transaction updates listener;
- explicit restore/sync operation;
- cancellation/pending/error states;
- test/mock store;
- optional generic subscription support even if Minik initially uses a non-consumable remove-ads product.

### 16.3 Current Apple API direction (checked 2026-08-30)

Use StoreKit 2. Current Apple documentation exposes verified `Transaction` values, `Transaction.currentEntitlements`, transaction update sequences, and `AppStore.sync()` for an explicit user-initiated restore/sync path. `AppStore.sync()` should be invoked only from explicit user action because it can prompt for App Store authentication.

For a one-time permanent “Remove Ads” purchase, a **non-consumable** In-App Purchase is the natural StoreKit product type unless the product owner explicitly chooses a subscription model.

These Apple details must be rechecked against official documentation at implementation/release time.

### 16.4 Minik adapter

Minik owns a thin adapter/configuration layer:

- product ID(s);
- mapping `removeAds` entitlement;
- localized purchase copy;
- Parent Area purchase UI;
- remove-ads reminder;
- ad service response to entitlement changes;
- App Store Connect setup.

The generic package must be usable by another app by supplying different IDs/configuration.

## 17. Remove Ads reminder

Required state:

- whether ads are already removed;
- reminder shown count/date/cadence;
- do not nag after entitlement active;
- presentation only in an adult-appropriate context if required;
- purchase and restore routes;
- persistence survives app relaunch.

## 18. Localization

Use Apple String Catalogs (`.xcstrings`) and keep these separate:

- interface strings;
- learned vocabulary/content;
- speech locale metadata.

Current foundation (2026-09-01):

- Apple String Catalogs exist for the full product set and the English Only target;
- the full catalog covers English, Amharic, Arabic, German, Spanish, French, Hebrew, Dutch, Brazilian Portuguese, European Portuguese, and Russian;
- the English Only catalog excludes Hebrew while retaining the other ten interface locales;
- deterministic validation and likely-hardcoded-literal audit scripts exist;
- the current audit reports **0 unreviewed likely user-visible hardcoded Swift literals** and validates referenced keys, locale coverage, shared-key parity, and English Only's Hebrew exclusion;
- all newly cataloged non-Android/iOS/Math copy has entries for each target locale; entries without an exact verified translation remain marked `needs_review`, so native-language linguistic QA remains a release gate.

Requirements:

- all hardcoded child/parent UI copy migrated to localization resources;
- verified Android interface locales implemented;
- English Only Hebrew-interface exclusion implemented centrally;
- complete-message localization, not concatenated fragments;
- RTL/LTR independent learning-content direction;
- math expressions remain mathematically ordered in RTL UI;
- screenshots/QA in long translations.

## 19. Artwork and assets

### 19.1 Language artwork

Current migration work already covers hundreds of vocabulary images. It remains a separate controlled stream until format/quality decisions are closed.

Known artwork corrections include previously identified wrong/ambiguous assets (for example dehumidifier/helix/cyan-turquoise issues from earlier audits).

### 19.2 Math artwork

Create a polished reusable object library with enough variety that quantity questions feel magical rather than repetitive.

Categories should include, after art direction approval:

- fruit;
- sweets/food;
- toys;
- balls/sports;
- animals/child-safe objects;
- school/nature objects;
- themed grouping/ten/array assets if needed.

Each object needs:

- transparent/background-safe rendering as appropriate;
- consistent visual scale;
- clear silhouette at small sizes;
- no embedded number that leaks the answer;
- licensing/ownership traceability;
- asset catalog naming/manifest.

The permanent generation/approval handoff is [`math-object-art-requirements.md`](math-object-art-requirements.md). It requires isolated single countable objects, neutral empty-container zero states, a coherent 6–8-theme baseline, small-size legibility, and source masters. Current procedural dots/shapes are development-only. Final source format remains subject to the real Xcode asset-format benchmark; do not generate or commit speculative final art merely to bypass that gate.

### 19.3 Minik mascot states

Need final production mascot assets/animations for:

- neutral/home;
- success;
- encouragement/failure;
- celebration/confetti;
- Soccer;
- Tower;
- Tic-Tac-Toe;
- Ping Pong (Math and standalone product);
- cards/learning where relevant;
- parent/home branding.

### 19.4 Product-aware frames and Ping Pong assets

**USER-CONFIRMED 2026-08-31:** `math_frame_background` is the Minik Math decorative frame for the same broad class of child-facing practice surfaces that use the Language decorative background. Selection is centralized/product-aware; Language remains unchanged. The artwork uses aspect-fill/crop without distortion and foreground surfaces retain readability. Ping Pong always uses `ping_pong_arena` instead.

Ping Pong and Math-frame assets are imported from `C:\Projects\Minik\artwork-staging\ping-pong` into separate explicit catalogs. `Resources/PingPongAssets.xcassets` belongs to Minik Math and Minik Ping Pong; `Resources/MathVisuals.xcassets` belongs only to Minik Math. Neither catalog is mixed with the Phase 41 vocabulary migration or accidentally added to Language targets.

## 20. Accessibility and responsive design

Mathematical content is never truncated or ellipsized: a missing digit/operator can change the answer. The shared presentation-fit order is normal layout, adaptive dimensions, font reduction only to the centralized readable minimum (currently 18 pt), wider/taller layout, then at most two lines as a last visual fallback. If content still does not fit, regenerate synchronously from the same level/skill/mechanic for at most 12 candidates, use an approved compact representation when available, or show a localized retry state. Soccer may reduce its pool to no fewer than four meaningful choices. Infinite regeneration and unreadably small tokens are forbidden.

Every final screen/activity must be tested for:

- smallest supported iPhone;
- large iPhone;
- iPad compact/full layouts;
- portrait/landscape as supported;
- Dynamic Type;
- VoiceOver labels/hints/actions;
- Reduce Motion;
- contrast/touch target sizes;
- safe areas/home indicator;
- independent RTL/LTR UI and content direction;
- cancellation of timers/speech/tasks on exit/background.

---

# PART VI — CURRENT iOS STATUS AS OF 2026-08-31

## 21. Repository/branch snapshot

### Main

Latest confirmed main product commit before the unattended sprint:

- `97e0462` — `Add Android-faithful language tower`

Earlier completed local/main commits:

- `561f52f8...` — Picture Memory correctness
- `7b9ebaa1...` — Language Mixed
- `4e81562c...` — Language Soccer
- `97e0462...` — Language Tower

### Sprint branch

Branch:

`codex-sprint-8h-20260830`

Checkpoint sequence:

- `387b402` — `checkpoint: start autonomous sprint` (empty safety checkpoint)
- `76b562b` — `checkpoint: add Android-faithful Tic-Tac-Toe`
- `a65da50` — `checkpoint: verify language production parity`
- `95d3f7d` — `checkpoint: complete Math levels 1-3` (name overstates release completeness; see below)
- `3370ac9` — `checkpoint: inventory Math levels 4-10`
- `02cf3d7b8a8e633ba8663b55667f9c95708359ca` — `checkpoint: fix post-sprint correctness findings`
- `c92cfe0c17dc654e701671c334bfaf5c6fa1acb1` — `docs: add canonical Minik master plan and UI references`
- `0d56c1b` — `checkpoint: make activity progress replay safe`
- `5f65ce4` — `checkpoint: add automatic math level foundation`
- `9eb8cec` — `checkpoint: prevent math presentation truncation`
- `c142411` — `checkpoint: complete functional M1 math slice`
- `66b526f` — `checkpoint: correct M1 retry timing`

**Remote verification before the 2026-08-31 Ping Pong sprint:** `origin/codex-sprint-8h-20260830` resolves to `c92cfe0c17dc654e701671c334bfaf5c6fa1acb1`. The Ping Pong checkpoint described below remains local unless explicitly pushed later.

## 22. Current project configuration

Current `project.yml` snapshot:

- minimum iOS deployment target: 17.0;
- Swift language version: 5.9;
- iPhone + iPad targeted;
- `MinikPlus`, `MinikPlusEnglish`, `MinikMath`, `MinikPingPong` targets;
- `Resources/GameAudio` included in the two Language targets;
- Language vocabulary/image resources included in the Language targets;
- unit-test target currently depends on `MinikPlus`.

The canonical production Apple identifiers are `com.appsbybros.minik.plus`,
`com.appsbybros.minik.plus.english`, `com.appsbybros.minik.math`, and
`com.appsbybros.minik.pingpong`; the test bundle uses
`com.appsbybros.minik.tests`. Apple/Firebase/AdMob/App Store registration and
matching configuration remain external release work.

## 23. Implemented/reviewed iOS capabilities

### Shared/foundation already present

- Swift/SwiftUI shared project architecture.
- Product configuration with Language / English Only / Math / Ping-Pong-only targets.
- Content contracts and semantic IDs.
- Generic sessions/views for multiple choice, build, pairs, memory, learn, cards, Soccer, Tower.
- learned-language direction/speech metadata infrastructure.
- current vocabulary normalization/catalog infrastructure.

### Language production

Static production parity gate now exposes exactly 13 Android-visible activities.

Deep independently reviewed recent phases:

- Picture Memory — implemented and corrected.
- Mixed — implemented.
- Soccer — implemented with Android-faithful educational/shot separation.
- Tower / Alphabet Blocks — implemented.
- Tic-Tac-Toe — implemented on sprint branch; extensive deterministic AI tests; static correction pass completed.

Other Language activities have production routes/providers, but must still pass final deep release audit against Android and global systems before the entire Language product is called release-complete.

### Tic-Tac-Toe correction status

The post-sprint correction fixed:

- invalid Swift factory trailing-closure binding syntax;
- AI unit random interval so it is `[0,1)`;
- regression tests for max RNG and 100% Medium probabilities;
- Games section copy.

Static review inspected the corrected source and structural searches found no remaining invalid factory-call pattern. No Swift parser/compiler was available in the Windows environment, so parsing/type-checking did not run; Xcode/XCTest/Simulator validation remains required.

### Math current functional slice

Core milestone: `MATH_EDUCATIONAL_CORE_FUNCTIONAL_WINDOWS_STATIC_COMPLETE` (2026-09-02). This is a Windows-static educational-core marker only; it explicitly does not claim Swift compilation, XCTest, Simulator/device validation, linguistic completion, commercial-system completion, or release readiness. Evidence and remaining gates are in `docs/math-educational-core-audit.md`.

The architecture retains all ten level identities and all thirteen product identities at every level. M1 through M10 now have coherent Windows-statically-validated implementations for all twelve educational activities at each level; Ping Pong remains the thirteenth non-curriculum activity. Automatic level selection is clamped to the highest implemented level, currently M10.

M1–M10 are **not release-complete**: each has a dedicated coherent production slice and the approved object/zero/grouping pack plus native fraction bars, number lines, percent bars, ratio groupings, signed-number placement, probability diagrams, and geometry diagrams are integrated, but Xcode asset compilation, device-scale visual QA, XCTest, Simulator/device interaction, speech, accessibility, and layout validation remain required.

### Ping Pong and Math visual-identity sprint

Implemented in the 2026-08-31 working tree/checkpoint:

- pure match scoring, target validation, two-point rule, and service rotation;
- four centralized tunings and persisted difficulty/mode/per-difficulty target;
- Starter drag/reach, full Tap, full Swipe, table-only Tap serving, difficulty-assisted but fallible Swipe serving, Minik serve, shared shot solver, deterministic flight/rally resolution, and incoming-shot-aware Minik AI with distinct miss/sound/imperfect-contact outcomes;
- SpriteKit scene embedded in SwiftUI with approved paddle/ball/arena/Minik pose assets, one arena-image-calibrated responsive table-coordinate mapping, lifecycle pause/cancel, Reduce Motion handling, and accessibility announcements/actions;
- Minik Math just-for-fun Ping Pong route outside `MathActivityKind`/curriculum;
- standalone `MinikPingPong` target/root with no curriculum, learned-language state, Parent Area, or activity hub;
- narrow host completed-match/action seam for future shared Ads/commerce/code systems, with no fake implementation;
- centralized Math practice-background selection using `math_frame_background`, leaving Language unchanged;
- deterministic unit-test source for match, controls, flight, serving, AI, persistence, product routing, and configuration.

Windows validation is limited to repository/static checks because Swift/Xcode/XCTest/Simulator are unavailable. macOS build, XCTest, SpriteKit/SwiftUI runtime behavior, asset compilation, device layout, accessibility, and final difficulty tuning remain mandatory.

## 24. Current artwork/migration state

The Phase 41 vocabulary catalog now has source-complete iOS coverage for all 543 image-capable items: 397 validated Android migrations, 8 deterministic local masters, 33 pinned licensed/public-domain acquisitions, and 93 individually generated and visually reviewed masters. The dehumidifier and helix Android-source errors have reviewed replacements without changing vocabulary identity or behavior. Xcode asset-catalog compilation, Simulator/device scale, accessibility, and final human art-direction QA remain open.

## 25. Current full-product completion estimate

This is an engineering estimate, not a promise and not simply a lines-of-code percentage.

As of 2026-09-13, after M1–M10, the Language source-parity gate, Parent/progress/records work, release-source integrations, and Phase 41 vocabulary-source closure:

- shared engines/foundation: approximately **85–90%**, depending on subsystem;
- Language mechanics/routes: approximately **90–95% source-functional**, lower when runtime/device and release-service validation are included;
- Math educational product: approximately **80–85% source-functional** across the approved M1–M10 × 12 educational matrix, lower when macOS/device validation and final tuning are included;
- Parent/progress/records: approximately **75–85%**, with local surfaces, rewards, and the Android-compatible Firebase boundary present but live backend/account/privacy validation still open;
- ads/commerce/notifications: source boundaries and Parent controls are implemented fail-closed; production account values, provider/policy approval, StoreKit/App Store setup, and device validation remain open;
- localization: source/catalog infrastructure and locale coverage are present; native-language linguistic QA remains incomplete;
- final artwork: all 543 vocabulary items and the approved Math object pack are source-ready; device-scale QA, final app icons, and remaining brand/mascot art decisions remain open;
- macOS/Xcode/TestFlight hardening: the latest supplied run built all four apps and executed 797 ProductConfigurationTests with one deterministic M3 test defect; that assertion was corrected afterward, but the repaired suite, new release-source integrations, and complete current asset catalog have not been rerun on macOS.

**Overall release-readiness engineering estimate: approximately 70–75%. This is not a delivery promise.**

This number should be updated only after meaningful phase completion, not after every small commit.

---

# PART VII — DEFINITION OF DONE

## 26. Definition of Done for one activity

An activity is not “done” because its enum, provider or session exists.

Before moving to the next activity in release-hardening mode, all applicable items must be satisfied:

- [ ] canonical product behavior documented;
- [ ] Android parity audited (Language/shared Android mechanics) or user-approved Math spec;
- [ ] content provider/round generation complete;
- [ ] correctness/session engine complete and deterministic;
- [ ] realistic distractors/answer uniqueness rules tested;
- [ ] SwiftUI interaction complete;
- [ ] success/failure/Minik feedback integrated;
- [ ] speech/audio behavior integrated;
- [ ] reward/progress events integrated;
- [ ] lifecycle cancellation correct;
- [ ] VoiceOver complete;
- [ ] Dynamic Type reviewed;
- [ ] Reduce Motion respected;
- [ ] independent RTL/LTR behavior reviewed;
- [ ] small iPhone/large iPhone/iPad reviewed;
- [ ] final/approved artwork used or an explicitly tracked release blocker exists;
- [ ] localization keys exist;
- [ ] deterministic unit tests exist;
- [ ] Xcode compiles relevant targets;
- [ ] XCTest passes on macOS;
- [ ] Simulator manual smoke test passes;
- [ ] master plan Living Status updated;
- [ ] clean isolated commit created and reviewed.

## 27. Definition of Done for the full product

Shipping requires all of the following:

- all approved Language activities complete;
- all approved Math levels/activities complete;
- English Only policy verified;
- home/navigation shell complete;
- points/streak/progress complete;
- Parent Area complete;
- Firebase records complete;
- ads complete and policy-compliant;
- remove-ads StoreKit entitlement complete;
- notifications complete;
- localization complete;
- artwork complete;
- privacy/parental gates complete;
- all four iOS targets build;
- automated tests green;
- device/Simulator matrix passes;
- TestFlight beta passes;
- App Store Connect metadata/privacy/IAP configured;
- final App Review policy check performed;
- release candidate archived/submitted.

---

# PART VIII — COMPLETE DELIVERY ROADMAP / SPRINT PLAN

The roadmap is deliberately long. It is safer to have an explicit finish line than to pretend the remaining app is one feature.

## PHASE A — Ground truth, safety, and buildability

### Sprint A0 — Canonical master plan
**Status:** CURRENT / document created 2026-08-30.

Deliverables:

- this file accepted as canonical;
- copy into `ios/docs/MINIK_MASTER_PLAN.md`;
- future Codex sessions instructed to update living status only;
- wrong “7 Math activities” mental model formally retired.

### Sprint A1 — Repository convergence and branch hygiene

Deliverables:

- verify local/remote `codex-sprint-8h-20260830` includes `02cf3d7`;
- review sprint commits before integrating to `main`;
- selectively merge/cherry-pick only approved work;
- preserve Phase 41 dirty asset work;
- replace/remove temporary unattended `AGENTS.md` exception after it is no longer needed;
- status/index clean for the feature baseline.

### Sprint A2 — Early macOS/Xcode baseline gate

Do this **early**, not only at the end.

Deliverables:

- generate/open project with Xcode/XcodeGen;
- build MinikPlus;
- build MinikPlusEnglish;
- build MinikMath;
- compile ProductConfigurationTests;
- run all current XCTest;
- fix compile-only issues accumulated during Windows work;
- record simulator/device warnings;
- establish a repeatable macOS validation checklist/CI strategy.

Exit criterion: current baseline really builds before adding another large layer.

---

## PHASE B — Shared product foundation required by every final activity

### Sprint B1 — Production activity catalog model

Deliverables:

- production activity identity separated from generic engine identity;
- exact 13 Language production activities retained;
- exact 13 Math production activity identities introduced;
- internal helper engines remain internal;
- menu/route metadata centralized;
- product-availability tests.

### Sprint B2 — Shared app shell/navigation

Deliverables:

- native SwiftUI Home/menu shell;
- branding/Minik placement;
- Home, Records, Parent Area navigation;
- sectioned cards;
- iPhone/iPad responsive layout;
- route ownership outside activity views.

### Sprint B3 — User/profile/local persistence foundation

Deliverables:

- versioned local store;
- profile/product state;
- learned language/interface locale/level settings;
- migration strategy;
- test store/in-memory implementation;
- Tic-Tac-Toe preferences migrated behind the shared persistence philosophy where sensible without overcoupling.

### Sprint B4 — Activity telemetry/progress event model

Deliverables:

- typed activity events;
- attempts/correctness/duration hooks;
- per-skill/per-level progress aggregation;
- no Firebase/ads/StoreKit dependencies in activity engines;
- deterministic tests.

### Sprint B5 — Points, streaks, rewards and records model

Deliverables:

- points rules/contracts;
- current/best streak;
- high-score/record model;
- achievement/level-up event seam if retained;
- local persistence;
- shared UI summary components.

### Sprint B6 — Shared Minik feedback system

Deliverables:

- success/failure/encouragement states;
- Minik mascot presenter;
- confetti/celebration component;
- reusable positive phrase policy;
- Reduce Motion behavior;
- cancellable feedback timelines;
- no per-activity duplicate animation infrastructure.

### Sprint B7 — Speech/audio architecture

Deliverables:

- learned-language speech service;
- interface/hosting-language feedback service;
- replay-button conventions;
- interruption/cancellation policy;
- audio effect player;
- lifecycle behavior;
- deterministic/mocked tests.

### Sprint B8 — Localization infrastructure

Deliverables:

- String Catalog structure;
- locale policy service;
- initial migration of shell/shared strings;
- English Only Hebrew-interface exclusion;
- RTL/LTR helper contracts;
- pseudo/long-string QA strategy.

### Sprint B9 — Progress/statistics UI foundation

Deliverables:

- parent-readable aggregates;
- progress cards/charts appropriate for iPhone/iPad;
- local data only initially if backend not ready;
- accessibility/localization.

---

## PHASE C — Language activities: one release-level audit at a time

These sprints use Android as the behavioral reference. Each sprint must satisfy the activity Definition of Done in §26 before moving to the next, except global commerce/ads may remain hooked through the already-created event boundary.

### Sprint C1 — Learn Letters release audit

Android study flow, examples/images, TTS/replay, levels/read-skill policy, success/progression, iPad/RTL, tests.

### Sprint C2 — Letter Pairs release audit

4 semantic pairs/8 images, speech, correct removal/scoring, lifecycle/accessibility, progress/rewards.

### Sprint C3 — First Letter picture→letter release audit

Exact retries/progression, speech/image behavior, plausible choices, reading-policy integration.

### Sprint C4 — First Letter letter→picture release audit

Reverse semantic mapping, image choice quality, speech, retry/progression.

### Sprint C5 — Picture→Word release audit

Image prompt, four learned-word choices, distractor quality, TTS, progress.

### Sprint C6 — Word→Picture release audit

Learned word prompt, four images, TTS, image readiness policy, progress.

### Sprint C7 — Build Word release audit

Ordered construction, duplicate letters, immediate correctness rules, speech, whitespace, keyboard/token accessibility.

### Sprint C8 — Mixed release audit

20/10/5 cadence, mode transitions, progress aggregation, capability/read-skill policy, exit/resume behavior.

### Sprint C9 — Word Cards release audit

Shuffle/manual/timed modes, looping, TTS/replay, level/category coverage, progress semantics.

### Sprint C10 — Soccer final release audit

Existing engine plus final visuals, intro/tutorial, Minik, speech/audio, rewards, global events, responsive/accessibility.

### Sprint C11 — Tower final release audit

Existing word-tower engine plus final visuals/feedback/global events, drag/drop accessibility, timing.

### Sprint C12 — Picture Memory final release audit

Picture↔picture semantics, exact-once speech, final card art, animations, progress/rewards.

### Sprint C13 — Tic-Tac-Toe final release audit

Compile/run exhaustive AI tests, persistence, UI timing, feedback, sounds, final mascot asset, localization, lifecycle, accessibility.

### Sprint C14 — Language production parity lock

Deliverables:

- all 13 deep audits green;
- no helper engine accidentally exposed;
- Language content/levels/categories coverage report;
- English/Hebrew learned-language matrix verified;
- shared progress/reward events verified across all activities.

---

## PHASE D — English Only product hardening

### Sprint D1 — English Only policy audit

Deliverables:

- English learned language fixed everywhere;
- learned-language selectors removed;
- Hebrew interface locale excluded;
- other supported UI locales available;
- all 13 activity routes work;
- no Hebrew learned-content persistence leakage;
- independent target tests.

### Sprint D2 — English Only visual/localization smoke matrix

Run representative activities in every supported interface locale, especially RTL Arabic with LTR learned English.

---

## PHASE E — Math curriculum authoring before more speculative code

Android is **not** consulted for a nonexistent Math curriculum. These are product-design sprints with user sign-off.

### Sprint E1 — Math global curriculum rules

Define once:

- semantic value types;
- numeric range policy;
- distractor framework;
- representation families;
- progression/difficulty dimensions;
- correct-answer uniqueness rules;
- when object quantities transition to grouped/symbolic representations;
- zero treatment;
- negative/fraction/decimal formatting;
- expression direction in RTL.

### Sprint E2 — M1 specification

For all 13 Math activities define exact M1 content, including the still-open full **Build Math** interaction. User signs off before implementation.

### Sprint E3 — M2 specification

Composition/decomposition/early +/- across all 13 activities, explicitly fixing current Tower/Pairs/Memory regression.

### Sprint E4 — M3 specification

Operations/relationships across all 13 activities; reconcile existing prototype with final product activities.

### Sprint E5 — M4 specification

Place value/numbers to 100/richer +/-.

### Sprint E6 — M5 specification

Multiplication/division meaning, arrays/groups/sharing.

### Sprint E7 — M6 specification

Fluency/factors/multiples/initial fraction relationships.

### Sprint E8 — M7 specification

Fractions/decimals as numbers.

### Sprint E9 — M8 specification

Fraction/decimal/percent/ratio relationships.

### Sprint E10 — M9 specification

Pre-algebra.

### Sprint E11 — M10 specification

Algebraic relationships/proportions/approved probability/geometry.

### Sprint E12 — Full Math 10×13 matrix review

One canonical matrix documents, for each `(level, activity)`:

- prompt form;
- answer form;
- generator/range;
- distractors;
- representation;
- progression;
- speech if any;
- why it teaches the current level's WHAT.

No code sprint begins without this matrix being internally consistent.

---

## PHASE F — Math representation/art foundation

### Sprint F1 — Math semantic/representation engine

Deliverables:

- quantity objects;
- grouped quantities;
- tens/ones/place-value representations;
- arrays/groups;
- number-line representation;
- direct numeral;
- arithmetic expression;
- missing-value expression;
- fractions/decimals/percent/ratio representations;
- equivalence/comparison semantics;
- accessibility descriptions.

### Sprint F2 — Quantity layout engine

Deliverables:

- adaptive object layout for small values;
- approved grouping transition rules;
- no answer leakage for zero;
- iPhone/iPad size adaptation;
- deterministic snapshot/layout tests where feasible.

### Sprint F3 — Math object artwork baseline

Produce/import enough final-quality objects (fruit, sweets, balls, etc.) to ship M1/M2 without placeholder dots. Manifest, licensing/source, naming and visual QA included.

### Sprint F4 — Higher-level Math visual assets

Ten-frame/grouping/arrays/place-value/fraction/number-line artwork and symbols as needed by approved curriculum.

### Sprint F5 — Level-aware distractor generator

Generic but curriculum-configured; guarantees exactly one correct answer, unique choices where required, plausible mistakes, deterministic tests.

---

## PHASE G — Math activities: one production activity at a time across approved levels

Each sprint takes one activity identity and implements it cleanly across M1–M10 according to the approved matrix. Do not call the sprint complete if only M1–M3 work.

### Sprint G1 — Learn Math

All levels; instructional cards/tables; object/expression representations; speech/replay if approved; progress as learning exposure rather than test accuracy.

### Sprint G2 — Math Pairs

Semantic pair generation per level; four pairs/round (or approved counts); final visuals/feedback/rewards.

### Sprint G3 — Build Number

Simple numeral/answer construction activity across relevant levels with a generic reusable numeric-input/token capability.

### Sprint G4 — Build Quantity

Reverse simple construction of quantity/representation; interaction clearly distinct from four-choice and full Build Math.

### Sprint G5 — Visual → Answer

Beautiful quantity/expression prompt + four plausible textual/numeric answers; exactly one correct.

### Sprint G6 — Answer → Representation

Target value + four visual/expression representations; exactly one correct.

### Sprint G7 — Build Math

Full ordered mathematical construction across levels; generic engine improvements only, no level-specific view hacks.

### Sprint G8 — Math Mixed

Level-specific cadence across approved Math modes; no unsupported activity invocation.

### Sprint G9 — Math Cards / Facts Table

Addition/multiplication/other approved fact tables; active cell highlighting; manual/timed looping; accessibility.

### Sprint G10 — Math Soccer

Fixed answer-ball pool, changing questions, duplicate physical values allowed where planned, confirmed score matrix, level-specific generators, final visuals/audio/rewards.

### Sprint G11 — Math Tower

Implement the user-confirmed target-count tower mechanic with extra blocks and delayed stable-correct completion; higher levels drive target from operations/representations.

### Sprint G12 — Math Memory

Equivalent representation pairs across all levels; silent by default unless explicit Math narration is approved.

### Sprint G13 — Math Ping Pong final integration

Complete Simulator/device tuning, final game/audio/accessibility review, and shared rewards/host-service integration for the non-educational Math Ping Pong destination. Language Tic-Tac-Toe remains separate.

### Sprint G14 — Math 10×13 production parity lock

All levels and activities audited; no fallback to easier content; full matrix tests; release checklist.

---

## PHASE H — Backend, records, parent product surface

Some foundation was built earlier; these sprints finish the real product.

### Sprint H1 — Firebase iOS backend integration

Records repository, App Check, environment config, offline/retry, backend contract audit against Android records.

### Sprint H2 — Records/high-score/leaderboard UI

Score/streak categories, new-record presentation, cached/offline states, name/identity flow if retained, localization and privacy.

### Sprint H3 — Parent Area complete

Language/level/settings/progress/notifications/commerce controls in a polished adult-facing modal/screen with parental gating where required.

### Sprint H4 — Statistics/progress complete

Per-level/skill/activity summaries, accuracy/time/streak as approved, clear child/parent semantics.

### Sprint H5 — Home shell rewards integration

Points/streak/records visible in the intended home/header locations, trophies/achievements, no duplicated state.

---

## PHASE I — Notifications and encouragement

### Sprint I1 — Notification service

Local scheduling, permission flow, localization, cancellation/rescheduling, mockable tests.

### Sprint I2 — Encouragement policy/settings

Parent toggle, cadence, content, inactivity/reminder rules, privacy-safe lock-screen copy, product variants.

---

## PHASE J — Ads and commerce

### Sprint J0 — Apple child/privacy/monetization policy decision gate

Before selecting ad/analytics behavior:

- verify current App Review Guidelines/Kids Category rules;
- decide App Store age band/category strategy;
- decide allowed ad provider/contextual mode;
- review Firebase analytics/data collection;
- document parental-gate requirements.

No ad SDK should be integrated before this gate.

### Sprint J1 — Reusable `AppStoreCommerceKit` Swift Package

Build/test the generic package described in §16 independently of Minik.

### Sprint J2 — StoreKit package test harness

StoreKit configuration files/sandbox scenarios, mocked store tests, purchase/pending/cancel/error/restore/entitlement/update flows.

### Sprint J3 — Minik Remove Ads adapter

Minik product IDs/configuration, entitlement mapping, Parent Area purchase/restore UI, instant ad disable.

### Sprint J4 — Ads provider integration

Policy-compliant provider, mock provider, interstitial opportunity rules, entitlement gating, lifecycle and error handling.

### Sprint J5 — Remove Ads reminder

Cadence/persistence, adult-safe presentation, no reminder after entitlement, localization.

### Sprint J6 — Monetization end-to-end QA

Sandbox purchase, restore on reinstall/new device, revoked/refunded behavior where testable, offline launch entitlement, ad suppression, all targets.

---

## PHASE K — Full localization and content QA

### Sprint K1 — Shared shell/Parent/records/commerce localization

All verified interface locales.

### Sprint K2 — Language activity localization QA

Every activity, including hosting-language TTS and independent learned-language direction.

### Sprint K3 — Math localization QA

Math-specific child copy, accessibility text and expression direction.

### Sprint K4 — English Only locale matrix

Hebrew exclusion plus all remaining locales.

---

## PHASE L — Artwork completion

### Sprint L1 — Language vocabulary image migration closure

Finalize image format, migrate/validate required assets, fix known bad artwork, manifest parity.

### Sprint L2 — Minik mascot/art state completion

Final mascot assets per product/activity/success state.

### Sprint L3 — Math artwork completion

Enough variety for every quantity/grouping representation and no placeholder artwork.

### Sprint L4 — App icons / launch / store creative source assets

Final branded icons and screenshot-ready UI.

---

## PHASE M — Global accessibility, responsive and lifecycle hardening

### Sprint M1 — Small/large iPhone pass

All shell/parent/activity screens.

### Sprint M2 — iPad pass

Adaptive spacing, larger scenes, no stretched phone UI.

### Sprint M3 — Dynamic Type / VoiceOver pass

Complete app audit.

### Sprint M4 — RTL/LTR pass

Arabic/Hebrew UI, English/Hebrew learned content independently, Math direction-neutral where needed.

### Sprint M5 — Reduce Motion / audio / lifecycle pass

Background/foreground, interruption, task cancellation, speech/audio ownership.

---

## PHASE N — Testing, performance and release engineering

### Sprint N1 — Unit/integration test completion

All sessions/providers/curriculum/persistence/rewards/commerce/backend mocks.

### Sprint N2 — macOS CI/build matrix

All four targets and tests on macOS. Use CI deliberately to control cost/minutes.

### Sprint N3 — Performance/memory/offline robustness

Large vocabulary/assets, image loading, repeated activity sessions, Firebase offline, entitlement offline.

### Sprint N4 — Privacy/security audit

Firebase data minimization, child-data rules, secrets/config, App Check, third-party SDK inventory, privacy manifest requirements current at release time.

---

## PHASE O — App Store / TestFlight / release

### Sprint O1 — App Store Connect product setup

For each shipping target/listing:

- register the canonical bundle IDs;
- app records;
- signing/capabilities;
- IAP product(s);
- sandbox testers;
- categories/age ratings;
- privacy details;
- localized metadata.

### Sprint O2 — TestFlight internal beta

Build upload, install/upgrade, entitlement/Firebase/notifications/assets validation.

### Sprint O3 — TestFlight external/real-device QA

Representative devices/locales, parent flow, children usability observations where appropriate.

### Sprint O4 — Store screenshots/previews/metadata

Final localized screenshots, descriptions, keywords, support/privacy URLs, no Android UI in Apple metadata.

### Sprint O5 — Release candidate freeze

No feature work; all blockers resolved; final regression and migration tests.

### Sprint O6 — App Review submission

Submit, respond to review, document any Apple-required product changes.

### Sprint O7 — Post-release verification

Production purchase, ads entitlement, Firebase records, notifications, crashes, App Store listing, rollback/hotfix plan.

---

# PART IX — LIVING STATUS (CODEX MAY UPDATE THIS SECTION)

## 28. Current active phase

**CURRENT 80’s PONG PARITY / SHARED MATH ENTRY — 2026-09-28: SOURCE IMPLEMENTED, APPLE VALIDATION PENDING.** The owner authorized committing the preceding Modern work (local commit `b15717f`, `main`; no push), matching current Android 80’s Pong, retaining both games inside Math and adding a standalone 80’s entry without a feature-mode parameter. `Resources/RetroPong` shares the current Android payload through a native SwiftUI/WKWebView host; `MinikRetroPingPong` is the new standalone scheme. Math routes to current Modern Simple or the same Retro game. This supersedes the older four-target and “Math routing unchanged” descriptions for these Pong entry points only; it does not change the Math curriculum. Android now has a Math app, but it was not used to redefine iOS curriculum in this task. Retro has no ads/Firebase; Modern’s existing Debug test ads are unchanged, pending future common ads-library work. Sixteen game and seven bridge tests, 191 Retro and 152 Modern source/asset checks, existing release/ads/commerce/test-source audits and six-file Swift grammar parse pass. Seven new native XCTest cases, compilation, WebKit rendering/audio and actual iOS play remain unverified. Browser discovery was empty; no Pixel/ADB, backend, push or workflow dispatch occurred. `docs/retro-pong-ios-handoff.md` contains the exact inventory, behavior and Apple checklist; a new manual-only Retro workflow is ready for owner dispatch after pushing.



**MODERN PING PONG ANDROID PARITY — 2026-09-28: IMPLEMENTED IN SOURCE, APPLE RUNTIME GATE PENDING.** The owner authorized current Android Modern parity in `ios-main-merge`, a shared Full/Simple entry parameter, no 80s changes, and no Pixel use. New native `Sources/ModernPong` contains the Android-derived engine/tuning/tutorial/art/audio plus house players, profiles, friendly games, tournaments, RTDB transport and test ads/StoreKit UI. The standalone root uses Full; Simple closes through a host callback and has no online/tournament/profile surfaces. Existing Math/legacy routing is unchanged. Firebase Apple registration for `com.appsbybros.minik.pingpong` has now been created in `minikswish`; the checked-in matching plist uses only `minikPingPong/`. No production rules/data, TripleShot, Android, Git or device mutations occurred. Windows source/asset audits and 43 isolated RTDB emulator tests pass. Native compilation, the 25 authored XCTest cases, Simulator/physical iOS, cross-platform live play and StoreKit runtime remain pending. See `docs/modern-pong-ios-handoff.md` for the exact change manifest, commands and release gates. This explicitly supersedes older statements that standalone Pong has no Firebase or purchase UI; Language/Math contracts remain unchanged.

**ACTIVE RELEASE-SOURCE HARDENING - 2026-09-14:** The independently implementable source work requested after the Language/Math/Ping Pong verification pass now includes complete source coverage for all 543 Phase 41 vocabulary images; Firebase-backed Language records with curated aliases, Parent opt-out/deletion, recoverable pending scores, and a distinct secure `v2_<UUID>` per product/profile; anonymous-authenticated query/write/delete transport; private immutable `leaderboard_owners/{player_id}` bindings that allow one Auth UID to own multiple profiles without exposing or substituting that UID; strict public field/type/value Rules and exact indexes; a selected archive/clear legacy cutover with an exact read-only-Android implementation handoff; local Parent-controlled reminders; Remove Ads integration; fail-closed child-directed ads rejecting known Google sample/test identifiers; canonical Apple identifiers and isolated production Firebase plists; DEBUG-only App Check debug selection and Release App Attest; exact privacy/App Store/signing handoffs; and targeted accessibility source gates. Updated iOS never claims a legacy public UUID and can republish retained local bests under its secure ID. Deployment remains intentionally blocked until the administrator archive/clear cutover and updated Android client are ready. These are Windows-static source milestones only. Apple/AdMob/App Store registration, external values, policy/legal approval, Android rollout, Firebase deployment/verification, macOS/Xcode compilation/tests, device behavior, privacy publication, TestFlight and App Store validation remain open.

**ACTIVE GITHUB-HOSTED SIMULATOR GATE - 2026-09-13:** The preferred manual-only workflow is now a dedicated full validation gate. Every dispatch attempts all four unsigned Simulator builds in one macOS job, runs ProductConfigurationTests exactly once after all four compilations are clean, boots one available modern iPhone Simulator, and sequentially installs, launches, observes, screenshots, diagnoses, and terminates every built app. Build, packaging, test, Simulator, and launch failures are aggregated only after short-retention evidence uploads. This is workflow/static readiness only until an authorized manual GitHub Actions run supplies real macOS results.

**ACTIVE LANGUAGE ANDROID-PARITY RECONSTRUCTION — 2026-09-06:** Started on `codex-sprint-8h-20260830` at `084ca2a3405700fa65841beadd3685ddcaec5d6c`. The owner's latest Simulator images and complete-product gate supersede earlier tap-only Soccer and static visual-lock claims. All 16 Android screenshots, layouts, assets and source are binding Language/shared visual references. Owner annotations are the minimum scope; known source discrepancies cannot be deferred to runtime.

The first source unit restores Intro → menu → activity navigation, Intro Parent entry, the original opening clip and full wordmark, Android phone/tablet menu proportions, a compact Language Parent dialog, and selected-interface-language lookup/catalogs. Learn now restores all original letter forms, separated word/picture regions, height-aware controls and the owner-required triangular Play-style replay affordance. Pairs now has a fixed 2x4 board and original timing/audio. Four choice compositions, typed host-clue Build, full reaction artwork/speech completion, real Android word rewards, and Cards viewport/timer repairs are implemented in source. Picture Memory now has its dedicated fixed 3x4 Android composition, exact pastel scene, automatic guarded transitions and clean continuous rounds while Math Memory remains unchanged. Language Tower now has its dedicated Android-derived loose-block/beach scene, locked bottom-up stack, guarded continuous rounds, original speech/failure feedback and verified fixed +2 completion integration while Math Tower remains unchanged. Language Tic-Tac-Toe now has its dedicated fixed Android-derived panel, exact board-holding mascot, full white-cell gradient board, guarded continuous rounds and preserved just-for-fun AI contract. Parent Levels opens the Android-derived Language difficulty destination with immediate persisted Auto/manual word A-E, Soccer A-C and Tic-Tac-Toe A-E/Random/Adaptive choices; the selected word stage drives production vocabulary providers without coupling to learned/interface language or Math. Soccer, Parent Levels/Language Auto, and final Mixed/system behavior are reconciled at source level. Mixed retains its exact repeating 20/10/5 typed children, identity-guards stale child callbacks, rolls failed construction back atomically, and cannot feed Android Write Auto evidence. The 13-route Language source gate is recorded as `ANDROID_PARITY_IMPLEMENTED_SOURCE`; `RUNTIME_VISUAL_VERIFICATION_PENDING` remains separate in the [second-Simulator correction ledger](language-second-simulator-correction-ledger.md) and parity lock.

Required final statuses are ANDROID_PARITY_IMPLEMENTED_SOURCE and, separately, RUNTIME_VISUAL_VERIFICATION_PENDING. New Swift source, XCTest, rendering, gestures, animation and audio need a real Mac/iPhone/iPad review. Selective local checkpoints only; no push, CI, workflow execution or Phase 41 staging. Math Level = WHAT / Activity = HOW and English Only policy remain unchanged.

**PREVIOUS MAC GATE REPAIR - 2026-09-05:** At the matching expected local HEAD `180155bedc7d421e3c5ffc391e943a32bffec604`, the latest supplied Xcode 26.6 / Swift 6.3.3 facts are all four apps BUILD SUCCEEDED and 797 ProductConfigurationTests executed: 796 passed, one M3 Build assertion failed. Classification before repair: TEST_DEFECT. Gate #6 commit `27ccca2` asserted the dedicated M3 provider's typed prompt on a test that instantiates the older generic factory, whose prompt is always `.mathExpression`. The corrected test verifies that factory's missing-addend prompt and complete ordered solution; new deterministic production tests retain strict typed semantics across the six-challenge session and all 16 M3 relationships. Production and the canonical Math contract are unchanged. A Windows boundary guard rejects the original assertion and is included in the standard test audit. Evidence: [M3 Build XCTest root cause](m3-build-xctest-root-cause.md). The repaired tests still require a real Mac rerun; one local checkpoint only, no push or CI.

**HISTORICAL STATUS - 2026-09-05:** The active product branch is `codex-sprint-8h-20260830`; this investigation started at `180155bedc7d421e3c5ffc391e943a32bffec604`. All four apps now have supplied compile-success evidence, and the latest real XCTest run passed 796 of 797 tests. The remaining M3 Build failure is a deterministic wrong-factory test assertion; its repair and added typed production regressions need Mac confirmation. Gate #6's prior claim that this assertion was resolved was incorrect. The no-CI product sprint restored the shared Minik visual foundation, corrected the reported Soccer and Ping Pong Simulator findings, audited Language speech paths, restored Parent Area visual parity, and continued the Windows-static Language audits without triggering GitHub Actions. The separate default-branch workflow-safety commit `2f00c04` remains intentionally outside the product branch and must not be merged merely for continuity.

M1 through M10 each have coherent twelve-activity production slices. M10 teaches two-step equations, linear relationships, proportions, probability, and rectangle measurement using validated typed representations, normalized `Rational` answer semantics, native probability/geometry diagrams, exact matching/choices, probability construction, ordered token grammar, and Answer Token Tower. Generated content is fit-gated, graded events carry the actual level, and Automatic readiness includes all ten levels. Every level remains pre-release pending macOS/Xcode/Simulator validation, visual QA, and native-language linguistic QA.

The educational products now have one localized Parent Area integrated into the shared shell. Minik Plus exposes persisted English/Hebrew learned-language selection; English Only displays fixed English without offering Hebrew; Math exposes Automatic/Manual mode and Level 1...Level 10 selection only while Manual; all use the central persisted interface-locale controller and a persisted encouragement preference. Minik Ping Pong remains outside this shell. No unconfirmed parental gate or notification cadence was invented.

Progress / Statistics now reads the replay-safe local repository through a deterministic product-filtered read model. It reports actual total typed attempts, first-attempt correct/accuracy, accumulated response time, recent practice, deterministic per-activity rows, and Math level/mode. Existing Math routes persist by exact production activity identity; Language choice/build/pairs/memory/Mixed plus specialized Soccer and Tower routes now persist typed attempts without Math fields. Soccer and Tower use stable word-plus-token challenge identities, per-token retry indices, actual educational correctness, and response duration while preserving their game/animation behavior. Learn, Cards, Tic-Tac-Toe, and Ping Pong are excluded from mastery. The UI explicitly says data is stored on this device and does not imply cloud history or synchronization.

Independent-review corrections now distinguish a stable practice-round presentation from semantic Language word/token identity. A repeated Soccer or Tower presentation of the same word and token starts again at attempt index 1, while retries inside that presentation increment normally and the persisted item ID remains semantic. The same correction pass made dynamic user-visible `String` production explicitly localized, including Soccer/Tower feedback and accessibility, hub subtitles, Parent/Progress paths, shared choice/build/memory feedback, Tic-Tac-Toe, and Ping Pong status copy. The current validator reports 592 keys in both catalogs across their 11/10-locale policies; newly added non-English fallback values remain `needs_review` rather than being represented as linguistically reviewed.

Records / Streaks now reads only the matching local reward-ledger scope. It shows actual current and best streak values when a ledger entry exists and an explicit empty state otherwise. It does not display or infer Math points, invent record history, or imply cloud synchronization.

The preferred Windows-accessible macOS gate is the manual-only GitHub Actions **iOS Simulator Build** workflow. Its only trigger is `workflow_dispatch`, with no partial-product or skip-test inputs: one macOS job attempts all four product builds and packages, records compile and package state separately, and runs ProductConfigurationTests exactly once using MinikPlus DerivedData only when all four compilations are clean. It then selects and boots one available modern iPhone Simulator and, for every built app, reads the real bundle identifier from that app's `Info.plist`, installs and launches it, waits for initial rendering, verifies the process remains present, captures a screenshot and console/process diagnostics, and terminates it before the next product. Four separately derived unsigned, universal Simulator ZIP artifacts remain; package-ready products still upload if a sibling fails. Three-day build-log, XCTest, and aggregate smoke-evidence artifacts preserve Simulator details, launch/console/process logs, screenshots, post-start crash reports, and a JSON per-product result without uploading DerivedData. A final step fails on any required compile, package, XCTest, Simulator, or smoke failure after all possible attempts and uploads. No signing credentials, production-service secrets, external test service, Maestro installation, or hosted AppStoreCommerceKit grace-period test is part of this gate. Historical non-GitHub configurations are not an approved validation path.

The second deliberate GitHub-hosted gate ran with Xcode 26.6 and iPhoneSimulator 26.5. All four requested products reached real Swift/resource compilation: the earlier `FoundationXML` blocker did not recur, String Catalog and asset-catalog compilation were reached, and the universal arm64 + x86_64 Simulator path was exercised. All four then failed on the same `PingPongScene` no-argument initializer missing its required `override` keyword and emitted the same `TicTacToeFeedbackPlayer` main-actor conformance warning. No product reached package-ready state, ProductConfigurationTests correctly did not run because the requested build set was not compile-clean, and no Simulator smoke test passed. The two diagnostics were corrected in `085d704`.

The third deliberate GitHub-hosted gate checked out exactly `085d704f5e8451ac9bc4456b4b521e6a64227c3b` and used Xcode 26.6 with iPhoneSimulator 26.5. XcodeGen succeeded and all four product schemes were attempted. `FoundationXML` remained fixed and the prior `PingPongScene` missing-`override` error remained fixed. All four builds nevertheless failed, exposing five distinct Swift compiler errors in `ParentAreaView`, `SoccerSession`, `LanguageWordCardsContentProvider`, `LanguageWordLevelContent`, and `MathM9ContentProvider`; `TicTacToeFeedbackPlayer` also continued to emit its delegate-conformance concurrency warning. No requested product became package-ready, ProductConfigurationTests did not run, and no Simulator smoke test has passed. This correction checkpoint addresses only those diagnosed source issues and the two other concrete Minik Swift warnings reported by the same run; a clean rerun remains pending. C1 and C2 remain Windows-static audited only, and C3 remains the first incomplete Language release audit.

The fourth deliberate GitHub-hosted gate checked out exactly `898a8e652691451b63fedad952ce4f81bf16b2a8` and used Xcode 26.6. The previous five Gate-3 compiler errors no longer recurred, and the previous Tic-Tac-Toe concurrency warning no longer recurred. The complete log contained four `error:` occurrences representing exactly two unique Swift source errors: `LanguageWordCardsContentProvider` used the wrong `LearningTextRepresentation` argument-label order, and `PairsView.mixedBoard` lacked an explicit return for its `LazyVGrid` modifier chain. All four requested builds still failed, no product was packaged, ProductConfigurationTests did not run, and a clean rerun remains pending.

The fifth deliberate GitHub-hosted gate checked out exactly `7bc15113f3c2b77dfbe3856558e4caf5e647c538` and used Xcode 26.6. MinikPlus, MinikPlusEnglish, MinikMath, and MinikPingPong all reported BUILD SUCCEEDED; all four Simulator ZIPs were successfully packaged and uploaded. The ProductConfigurationTests phase started, but test-target compilation failed before XCTest execution on exactly one unique compiler error: `LanguageWordLevelContentTests.swift` omitted the now-required `stableKey` argument when constructing `LanguageVocabularyImageManifestEntry`. The same test compile emitted one Minik warning because interpolating optional `androidWordID` produced a debug description. No XCTest assertions executed, so full CI green is not yet established; a clean Mac test rerun remains pending.

The sixth deliberate GitHub-hosted gate checked out exactly `b1c3e811da1dc72e3c0204c82e6c9596b8d85a9c` and used Xcode 26.6. MinikPlus reported BUILD SUCCEEDED, the ProductConfigurationTests target compiled, its XCTest bundle loaded in the Simulator, and 763 tests executed—the first real full ProductConfigurationTests execution. The run reported 18 assertion/error occurrences and exactly 8 unique failing test methods. The supplied correction brief nevertheless enumerates nine method names because it lists both ActivityProgress methods separately; this correction covers every enumerated method: `testTicTacToeIsAJustForFunGameInBothLanguageProductsOnly`; `testLocalRepositoryPersistsAndRestoresVersionedSnapshot`; `testReducerAggregatesAttemptsOutcomesCompletionAndDuration`; `testBuiltDisplayTextRestoresWhitespaceWhenFollowingTokenIsAccepted`; `testWhitespaceIsNotDraggableAndProgressiveDisplayPreservesIt`; `testExpectedVisibleSequenceReconstructsExactLearnedWord`; `testCatalogMigratesLevelAFruitsInAndroidSourceOrder`; `testM3BuildKeepsTheMissingValueTaskInsideTheBuildInteraction`; and `testDecorativeAreaIsNotPlayableTableInput`. The failures are stale or numerically over-exact test assumptions, including one already-correct dirty Phase-41 test hunk; repository evidence found no production defect. A clean macOS XCTest rerun remains required before claiming the suite passes.

**Gate #6 correction addendum — 2026-09-05:** The historical assertion that every named test was corrected is superseded for M3 Build. `27ccca2` replaced a wrong structure-ID parser with a typed-prompt assertion for the wrong factory. The latest real run passed 796/797 tests and failed that assertion. Source tracing establishes TEST_DEFECT, with no random-value dependency. The older factory's semantic test is now corrected, while new dedicated M3 tests enforce the unchanged typed production contract. See [root-cause evidence](m3-build-xctest-root-cause.md); repaired XCTest execution remains pending.

`project.yml` currently gives the `MinikApplication` template the complete `Sources` directory, so every application target compiles Language, Math, Tic-Tac-Toe, and Ping Pong sources even when runtime product routing excludes those features. This explains why both diagnostics appeared in all four products. Runtime product policy is not thereby incorrect. A target-source split may reduce compile coupling and build time, but it requires a separate dependency analysis and is deferred to a coherent build-architecture unit.

All current workflows under `.github/workflows/` are manual-only after corrective checkpoint `5b64a3a`. The pre-existing **iOS CI** workflow had been the only file with automatic `push` and `pull_request` triggers; those triggers were removed without changing its build/test logic or the separate Phase 41 benchmark work.

The reviewer-supplied log for GitHub Actions run `91194820829` establishes the first concrete Apple compile failure: XcodeGen completed, then MinikPlus compilation could not resolve `FoundationXML` because `LanguageVocabularyCatalogLoader.swift` imported that split module unconditionally. Checkpoint `8eac5e6` keeps `Foundation` unconditional and imports `FoundationXML` only when `canImport(FoundationXML)`, preserving the existing `XMLParser` behavior across Darwin and non-Darwin toolchains.

The Windows-static portion of C1 Learn Letters is now audited against Android. Language Learn preserves the exact 26-card English and 27-card Hebrew sequences, examples, illustration identifiers, final-form speech metadata, letter-then-word speech/replay, learned-language product policy, and Android's full-alphabet instructional policy. Its final action now uses the reviewed localized “Start over” copy and loops to the first card instead of ending. The generic Learn engine retains complete-after-final behavior for non-Language callers. The focused audit and remaining device gates are recorded in `docs/language-learn-release-audit.md`; the missing decorative Android lowercase/capital letter-mascot artwork remains an explicit visual parity decision/blocker.

The Windows-static portion of C2 Letter Pairs is now audited against Android. Its production route presents four semantic learned-language initial groups as eight globally unique mixed image tiles, permits any-two selection without leaking internal left/right identities, speaks each newly selected physical tile's English/Hebrew learned word, loops to a fresh board after completion, and records replay-safe semantic attempts plus the verified Android `+1/-1` points rule without a streak. Generic column-based Pairs behavior, including Math, remains unchanged. Evidence and remaining macOS/device/shared-feedback gates are in `docs/language-letter-pairs-release-audit.md`.

The Windows-static portion of C3 First Letter picture→letter is now audited against Android. It preserves image-ready same-category prompts, four distinct plausible initial choices, English/Hebrew learned-language speech, six-challenge retry-until-correct progression, and product language policy. The production route now uses the localized starting-letter instruction, exposes the actual pictured learned word to VoiceOver, and records the stable expected initial concept while keeping the UUID-based challenge instance separate for retries/lifecycle. Evidence and remaining Apple-platform gates are in `docs/language-first-letter-choice-release-audit.md`.

The Windows-static portion of C4 First Letter letter→picture is now audited against Android. It preserves one English/Hebrew initial prompt, four unique image-ready same-category pictures with distinct plausible initials, learned-word choice speech, six-challenge retry-until-correct progression, and exact initial-concept correctness. The production route now uses its localized picture-matching instruction, exposes each pictured learned word to VoiceOver, and records stable semantic progress separate from challenge-instance identity. Evidence and remaining Apple-platform gates are in `docs/language-first-letter-picture-release-audit.md`.

The Windows-static portion of C5 Picture→Word is now audited against Android. It preserves one image-ready prompt, four distinct same-category English/Hebrew learned-word choices, prompt/replay and choice speech, six-challenge retry-until-correct progression, exact vocabulary-word correctness, and product policy. The production route now uses its localized picture-to-word instruction, exposes the actual pictured learned word to VoiceOver, and records stable vocabulary identity separate from challenge-instance identity. Evidence and remaining Apple-platform gates are in `docs/language-picture-to-word-release-audit.md`.

The Windows-static portion of C6 Word→Picture is now audited against Android. It preserves one English/Hebrew learned-word prompt, four distinct image-ready same-category choices, prompt/replay and choice speech, six-challenge retry-until-correct progression, exact vocabulary-word correctness, and product policy. The production route now uses its localized word-to-picture instruction, exposes each pictured learned word to VoiceOver, and records stable vocabulary identity separate from challenge-instance identity. Evidence and remaining Apple-platform gates are in `docs/language-word-to-picture-release-audit.md`.

The Windows-static portion of C7 Build Word is now audited against Android. It preserves unique physical duplicate letters, immediate-prefix correctness, retryable unconsumed errors, English/Hebrew direction and speech, six image-ready challenges, and product policy. Typed word-build content retains exact whitespace while exposing only visible letter tokens; the UI restores progressive spaces, uses word-specific Minik presentation/accessibility, and now records the immediate per-token attempts that were previously absent. Evidence and remaining Apple-platform gates are in `docs/language-build-word-release-audit.md`.

The Windows-static portion of C8 Mixed is now audited against Android. It preserves the approved repeating 20 Word-to-Picture / 10 Picture-to-Word / 5 Word Build schedule, advances only for real child challenge transitions, atomically rolls back a failed mode change, and uses capability-enabled Level A content. Each child now receives its activity-specific presentation instead of a generic choice/build presentation. Choice modes retain learned-language speech, retry indices, and stable vocabulary identity; Word Build retains immediate-prefix per-token evidence under `.mixed`; no Math fields are introduced. Evidence and remaining Apple-platform gates are in `docs/language-mixed-release-audit.md`.

The Windows-static portions of C9 Word Cards and C10 Soccer are now audited against Android. C9 restores the dedicated Cards composition and identity-guarded manual/timed continuous shuffled flow without graded attempts. C10 now uses a dedicated Language-only drag game rather than the old shared tap/random presentation: real drag-vector football flight, shared-coordinate goal/keeper/post/crossbar collision, rebound, shot-identity exact-once finalization, the Android score matrix and retry/duplicate/continuous-word semantics, specialized telemetry, speech, lifecycle cancellation, RTL/LTR, accessibility fallback, and Reduce Motion. Persisted Parent Soccer A/B/C drives Android-derived keeper size, initial motion pattern, sweep timing/range, and post-ten-shot performance adjustment. Math Soccer is unchanged. Its typed full-pool boundary now feeds the separately audited Android-derived global Language Auto word-level mechanism. Evidence and remaining Apple-platform gates are in `docs/language-word-cards-release-audit.md` and `docs/language-soccer-release-audit.md`.

The Windows-static portions of C11 Tower and C12 Picture Memory are now audited against Android. C11 now uses a dedicated Language-only exact pastel scene with the original sitting gift-block mascot, sand and pile; scattered physical blocks; locked base; bottom-up semantic stack including whitespace spacers; non-consuming failure sound; completion confetti; final letter-to-word speech; typed telemetry; fixed verified +2 reward; and presentation-scoped continuous-round cancellation. The generic Math Tower path is unchanged. C12 locks the Games grouping, blank gradient card backs, physical-versus-semantic identity, image-to-identical-image pairs, exact-once accepted reveal speech, silent generic Math path, continuation/completion behavior, accessibility, and responsive grid. Evidence and remaining Apple-platform gates are in `docs/language-tower-release-audit.md`, the reconstruction ledger/crosswalk, and `docs/language-picture-memory-release-audit.md`.

The Windows-static portion of C13 Tic-Tac-Toe is now audited against the complete live Android source and layouts. Its dedicated just-for-fun route restores the exact pastel panel, board-holding gameplay mascot, inside branded close, gradient title, X/O controls and complete purple/pink/teal-edged white 3x3 board without ordinary-phone scrolling. Child-first rules, all seven level identities, Android Random/Adaptive compatibility, synchronous single AI response, hidden cumulative game scores, feedback/speech/sounds, accessibility, RTL-safe spatial board, and lifecycle/Reduce Motion behavior remain intact. The session score invariant persists across rounds, but no score is rendered to the child and no mastery event is emitted. Evidence and remaining Apple-platform gates are in `docs/language-tic-tac-toe-release-audit.md`.

The post-C14 independent-review correction also reconciles Soccer's instruction contract with the actual iOS interaction. Android uses a drag-across-release-line gesture, while the intentional iOS implementation uses native buttons for one-action tap-to-kick. The 11 Full and 10 English Only interface-locale introductions now describe tap only, and the same localized String is used for visible and spoken instructions. Soccer scoring, ordered-token correctness/retry behavior, speech, telemetry, and Math Soccer remain unchanged.

C14 now locks all 13 production Language identities together at Windows-static level. The machine-audited record captures Android behavior/reference sources, exact menu art/provenance, section and session identity, speech, progress/reward and retry rules, lifecycle, accessibility, RTL/LTR, and an explicit pending runtime gate for every activity. The lock rejects Picture Memory section drift, child-visible generic engines, incomplete/wrong production artwork, a child-Home learned-language selector, graded Cards/Tic-Tac-Toe, lost Soccer/Tower semantic telemetry, and false runtime-confirmed claims. Evidence is in `docs/language-production-parity-lock.md` and `docs/language-production-parity-lock.tsv`.

Gate #6 runtime QA observations remain separate from the XCTest correction. Their current Windows-static disposition is:

- The shared Language visual foundation, illustration-led Home/Learn surfaces, and original Minik activity art are implemented; focused activity audits and Apple-device visual confirmation remain incomplete.
- Picture Memory is now grouped under Games in production and covered by a deterministic catalog test; runtime menu confirmation remains pending.
- Soccer balls now render their ordered-token letters over the original field/goalkeeper art; runtime layout and interaction confirmation remain pending.
- Shared success/failure feedback and reduced-motion-safe reactions are implemented; timing and presentation still require runtime confirmation.
- Language speech sources and lifecycle paths pass the static audit, but audible output in Appetize/on device remains unconfirmed.
- Ping Pong serve targeting now uses root-scene coordinates and the original table/mascot composition; runtime feel and hit targeting remain pending.
- Ping Pong typography and composition were corrected statically but still require iPhone/iPad visual confirmation.

**Completed no-CI audit units:** Windows-static portions of Language C1-C14, including the post-C14 independent-review corrections; D1-D2 English Only hardening; and the focused Math visual-consistency pass. Math now has an activity-by-activity M1/M5/M10 visual record across all 13 identities, shared Math frame/light surfaces, branded close/replay/feedback boundaries, precise typed representations, and explicit LTR mathematics without learned-language state. There is no Android Math authority, and no Math curriculum, correctness, progression, reward, or telemetry behavior changed. The clean macOS rerun, ProductConfigurationTests, and every recorded runtime/device/independent-review gate remain required before any release-complete claim. Those historical audit units did not add automatic triggers, caches, signing, Firebase, StoreKit, ads, notifications, or unapproved Math reward values; later explicitly assigned release-integration work is recorded separately below.

## 29. Sprint status board

Use these markers: `[ ] not started`, `[~] in progress`, `[x] completed and independently reviewed`, `[!] blocked`.

- [x] A0 Canonical master plan integrated and factually validated — 2026-08-30
- [~] P1 Modern/Retro Android parity and Math integration — source complete 2026-09-28; local commits authorized; Apple builds/tests/runtime pending
- [~] P0 Unified Ping Pong / Math identity / fourth product — implemented 2026-08-31; macOS validation and independent review pending
- [ ] A1 Repository convergence/branch hygiene
- [~] A2 macOS/Xcode baseline gate - latest supplied run built all four apps and passed 796/797 tests; remaining M3 Build TEST_DEFECT classified and repaired with deterministic typed production coverage and a Windows boundary guard; repaired XCTest confirmation pending
- [~] B1 Production activity catalog model — 13 Math identities implemented and statically reviewed; macOS validation pending
- [~] B2 Shared app shell/navigation — educational Parent Area, progress/records, reminders, gated commerce, and configurable privacy/terms/support/version destinations are source-integrated; runtime validation and externally hosted release content remain
- [~] B3 User/profile/local persistence — interface locale, learned language, Math level mode/state, encouragement, and product/profile-scoped public alias/participation/pending state persist locally; final multi-profile UX remains open
- [~] B4 Activity telemetry/progress event model — replay-safe typed events and one shared outcome-dispatch boundary are wired through M1–M10 and supported graded Language routes, including specialized Soccer/Tower ordered-token attempts; remaining Language deep-audit coverage and macOS validation remain
- [~] B5 Points/streak/rewards/records model — typed central policy/processor, versioned local ledger, idempotency, all Android-observed production Language reward mappings, aggregate remote-record submission, curated public alias activation/pending publication plus Parent opt-out and deletion, and truthful local streak UI implemented; unapproved Math policy and macOS/backend validation remain
- [ ] B6 Shared Minik feedback
- [~] B7 Speech/audio architecture — existing Language speech preserved; typed selected interface locale drives InterfaceSpeech and Tic-Tac-Toe hosting voice; M1–M9 Learn/Cards/Tower replay wired; macOS validation pending
- [~] B8 Localization infrastructure — two String Catalog policies, 11/10-locale coverage and key-parity validation, plus direct-literal and dynamic-String boundary audits implemented; native-language QA remains
- [~] B9 Progress/statistics UI foundation — deterministic local read model and accessible educational UI implemented; specialized Soccer/Tower telemetry is connected, while macOS validation and later product hardening remain
- [~] C1 Learn Letters release audit — Windows-static parity audit and focused tests authored; macOS/device/VoiceOver/visual QA and decorative letter-art decision pending
- [~] C2 Letter Pairs release audit — Android semantic board, learned-word speech, continuous rounds, typed progress/rewards, accessibility, and focused tests audited on Windows; macOS/device/shared final-feedback validation pending
- [~] C3 First Letter picture→letter release audit — Android behavior, explicit presentation, speech, plausible choices, retry progression, semantic progress identity, and accessibility audited on Windows; macOS/device validation pending
- [~] C4 First Letter letter→picture release audit — reverse semantic mapping, image readiness/quality, speech, retry progression, semantic progress identity, and accessibility audited on Windows; macOS/device validation pending
- [~] C5 Picture→Word release audit — image prompt, word choices, distractor identity, speech, retry progression, semantic progress identity, and accessibility audited on Windows; macOS/device validation pending
- [~] C6 Word→Picture release audit — learned-word prompt, image choices, image readiness, speech, retry progression, semantic progress identity, and accessibility audited on Windows; macOS/device validation pending
- [~] C7 Build Word release audit — typed word identity, duplicate letters, immediate-prefix correctness, whitespace, speech, semantic per-token progress, and accessibility audited on Windows; macOS/device validation pending
- [~] C8 Mixed release audit — 20/10/5 capability-aware cycle, atomic transitions, typed child presentations, speech, semantic choice progress, per-token Build progress, and focused tests audited on Windows; macOS/device validation pending
- [~] C9 Word Cards release audit — dedicated Android composition, learned-text-only continuous shuffled bags, manual/timed advance, speech/lifecycle, product policy, and non-graded semantics audited on Windows; macOS/device validation pending
- [~] C10 Soccer final release audit — dedicated drag/vector/physical-collision game, Android score matrix, retries, duplicate physical IDs, continuous words/pool boundary, A/B/C keeper contract, specialized telemetry, speech, exact-once lifecycle, direction, accessibility and Reduce Motion audited on Windows; macOS/device validation pending
- [~] C11 Tower / Alphabet Blocks — dedicated Android-derived pastel scene with scattered physical blocks, exact canonical beach/gift foreground, colored locked-base bottom-up stack, whitespace, duplicates, continuous guarded words, final letter→word speech, failure sound, confetti, fixed +2 reward, specialized telemetry, lifecycle, direction, accessibility and Math isolation audited on Windows; macOS/device validation pending
- [~] C12 Picture Memory — dedicated fixed 3x4 Android-derived scene, 12 physical/6 semantic image pairs, exact-once reveal speech, automatic identity-guarded transitions, continuous clean rounds, accessibility and Math isolation audited on Windows; macOS/device validation pending
- [~] C13 Tic-Tac-Toe — exact pastel scene and board-holding mascot, fixed no-scroll phone composition, game rules/levels/AI, hidden cumulative scores with a source guard against rendering, feedback/speech/sounds, accessibility, lifecycle, and just-for-fun semantics audited on Windows; macOS/device validation pending
- [~] C14 Language production parity lock — all 13 identities and regression-fail conditions locked by a machine-audited source/provenance/runtime-gate record; macOS/device/independent review pending
- [~] D1 English Only production policy — fixed English, 10 interface locales, Parent policy, 13-route/art/speech/product-isolation contracts audited on Windows; macOS/device validation pending
- [~] D2 English Only localization / visual lock — current 592-key/10-locale parity, no Hebrew state, Arabic RTL/English LTR, and key production surfaces audited on Windows; macOS/device validation pending
- [~] E1–E12 Math curriculum specification/matrix — all ten level pools and thirteen identities are implemented; content tuning and macOS validation remain
- [~] F1–F5 Math representation/art/distractors — typed representations, operational fit, approved initial object/zero/grouping catalog, and deterministic distractors are implemented; higher-level art and macOS validation pending
- [~] G1–G14 Math activities/parity lock — all twelve educational identities are functionally coherent and routed at M1–M10; release validation remains
- [~] Math visual consistency — all 13 identities recorded at representative M1/M5/M10, specialized replay uses owned Minik art, shared frame/surface/feedback and LTR contracts audited on Windows; macOS/device validation pending
- [~] H1–H5 Backend/records/parents/home — Firebase anonymous transport gates every query/write/delete and preserves pending scores across auth/config failure; Android-compatible top-20 score/streak repositories, secure versioned per-profile IDs, private immutable Auth ownership bindings, curated aliases with Parent change-alias control and no free text/local names, alias-selection activation, Parent opt-out/deletion, cache/error states, isolated Language plists, DEBUG-only App Check debug configuration, Release App Attest, strict repository Rules/indexes, local Parent Area, and Progress / Statistics are implemented at source level. Updated Android implementation, administrator archive/clear cutover, Rules/index deployment, App Check registration/metrics/enforcement decision, legal/policy review, and macOS/backend validation remain
- [~] I1–I2 Notifications — Parent-only opt-in, persisted weekly local reminder, lifecycle repair, disable/cancel, localized copy, and deterministic source tests implemented; Xcode/device authorization and delivery validation plus final cadence/copy approval remain
- [~] J0–J6 Ads/StoreKit/remove ads — reusable package retained; app startup/update/foreground reconciliation, injected non-consumable Remove Ads configuration, cached entitlement, gated Parent purchase/restore/status, and deterministic source tests implemented. The Google provider adapter and shared ad-service boundary fail closed behind explicit enablement, child-policy approval and injected provider IDs, reject known sample/test identifiers, apply child-directed/under-age/G/non-personalized configuration, suppress on `remove_ads`, and receive Android-derived Language plus owner-approved Ping Pong opportunities. The Android-derived two-day/fourteen-day reminder is source-integrated and can appear only when real ads and a loaded purchase are available. Policy approval, production IDs, per-product enablement decisions, and StoreKit/ad device validation remain
- [ ] K1–K4 Localization QA
- [ ] L1–L4 Artwork completion
- [~] M1–M5 Accessibility/responsive/lifecycle — targeted source audit covers production icon labels, 44-point control minima, non-color-only answer feedback, and detectable leading/trailing mistakes; full VoiceOver/Switch Control/Dynamic Type/RTL/lifecycle/device validation remains
- [~] N1–N4 Testing/performance/privacy — deterministic XCTest source covers the implemented integrations, all 40 repository Windows audit/validator entry points pass, app-owned privacy manifests describe current `UserDefaults` plus Language record usage, and exact website/privacy-inventory source handoffs exist; XCTest execution, performance/offline stress, archive privacy reporting, SDK/account review, legal approval/publication, and Apple-platform validation remain
- [~] O1–O7 App Store/TestFlight/release — per-target bundle/version/icon configuration, production Language Firebase plists, a shared explicit version/build strategy, and a four-product checklist classified as repo-ready/owner action/Mac-required are checked in; Apple/Firebase/AdMob account actions, signing, final metadata, screenshots, archives, TestFlight, review submission, and production verification remain external/runtime work

## 30. Known open product decisions

Do not silently choose these:

1. Exact higher-level representation breakpoints and content pools within the confirmed M2–M10 curriculum.
2. Exact per-level Math Mixed cadence and Cards/facts pacing within their confirmed contracts.
3. Final profile model: one child vs multiple child profiles.
4. Final legal/consent/privacy-policy wording, retention policy, and deployed-rule approval for the public leaderboard.
5. App Store category/age-band strategy and resulting advertising/analytics constraints.
6. Remove Ads business model if anything other than one-time non-consumable is desired.
7. Notification cadence/copy.
8. Final App Store listings and product IDs.

## 31. Current release blockers

- The current XCTest gate remains red: the latest supplied Xcode 26.6 / Swift 6.3.3 run built all four apps and executed 797 tests, with one M3 Build failure. The older-factory assertion introduced by `27ccca2` was deterministically wrong; this checkpoint corrects it and adds typed production regressions without production changes. Windows/static evidence cannot establish that the repaired tests compile and pass. A future authorized Mac rerun is still required.
- All four targets currently compile the complete `Sources` directory through the shared `MinikApplication` template. This is a compile-time coupling/optimization issue requiring later dependency analysis, not evidence of incorrect runtime product routing.
- Canonical Apple bundle IDs are source-configured for all four apps and the test bundle. Matching production Language Firebase plists are source-wired with pre-copy bundle-ID validation, and Release App Attest source configuration/entitlement is present. Apple Developer/App Store Connect registration, Firebase App Check app registration/metrics, any approved AdMob iOS app registration/IDs, signing, and archive validation remain external gates.
- M1–M10 have twelve functional educational activities each, but macOS/Xcode/Simulator validation and final visual/content tuning remain required.
- The Math contract is user-confirmed, but exact higher-level pools/tuning still require activity-by-activity authoring and review.
- Educational Parent Area, local Progress / Statistics, local and remote Records / Streaks, specialized Language Soccer/Tower telemetry, reminders, gated commerce, and gated configurable privacy/terms/support/version information are implemented at source level. Production URLs/content, backend account configuration, and macOS/device validation remain incomplete.
- The reusable StoreKit package is integrated into all shared-source targets. The app observes transaction updates at startup, refreshes at startup/foreground, supports explicit restore, maps the injected non-consumable to `remove_ads`, persists a launch cache, and exposes purchase/restore/status behind a randomized adult arithmetic gate in Parent Area for MinikPlus, MinikPlusEnglish, and MinikMath. Standalone MinikPingPong has no commerce surface, so its ads must remain disabled absent a separately authorized UX decision. The production Google adapter, deterministic cadence, and Android-derived reminder policy are source-integrated but fail closed until App Store category/age-band policy, explicit enablement, and real iOS AdMob app/unit IDs are supplied; known sample/test identifiers are rejected. App Store Connect setup and StoreKit/Xcode/ad-device validation remain incomplete.
- Local learning reminders are implemented at source level with a default-off Parent toggle, contextual Apple permission request, conservative weekly repeating schedule, per-product persistence, lifecycle-safe repair, cancellation, and localized privacy-safe copy. Xcode/device authorization, Settings-revocation, delivery, locale-change, and final cadence/copy approval remain incomplete.
- Final localization QA incomplete: the deterministic source/catalog audit is zero, but newly supplied fallback entries still require native-language linguistic review.
- C1 Learn Letters is Windows-statically audited, but macOS speech/lifecycle, iPhone/iPad, VoiceOver, mixed RTL/LTR, and native-language QA remain. Android's 106 decorative lowercase/capital letter-mascot drawables are not represented in the tracked iOS asset catalog; iOS currently uses native letter text, so that visual difference requires explicit approval or asset work.
- C2 Letter Pairs is Windows-statically audited, but macOS compilation/XCTest plus device speech, rapid-interaction, points persistence, VoiceOver, mixed RTL/LTR, layout, and final shared success/failure feedback QA remain.
- C3 First Letter picture→letter is Windows-statically audited, but macOS compilation/XCTest plus device image rendering, English/Hebrew speech, retry timing, VoiceOver, mixed RTL/LTR, Dynamic Type, and final visual QA remain.
- C4 First Letter letter→picture is Windows-statically audited, but macOS compilation/XCTest plus device image rendering, English/Hebrew speech, retry timing, VoiceOver, mixed RTL/LTR, Dynamic Type, and final visual QA remain.
- C5 Picture→Word is Windows-statically audited, but macOS compilation/XCTest plus device image rendering, long-word layout, English/Hebrew speech, retry timing, VoiceOver, mixed RTL/LTR, Dynamic Type, and final visual QA remain.
- C6 Word→Picture is Windows-statically audited, but macOS compilation/XCTest plus device image rendering/grid, English/Hebrew speech, retry timing, VoiceOver, mixed RTL/LTR, Dynamic Type, and final visual QA remain.
- C7 Build Word is Windows-statically audited, but macOS compilation/XCTest plus device tap/drag, duplicate-letter and multiword interaction, English/Hebrew speech sequencing, VoiceOver/keyboard/Switch Control, mixed RTL/LTR, Dynamic Type, and final visual QA remain.
- C8 Mixed is Windows-statically audited, but macOS compilation/XCTest plus device 20/10/5 transitions, continuous repeat, English/Hebrew speech, retry/telemetry exactness, VoiceOver/keyboard/Switch Control, mixed RTL/LTR, Dynamic Type, and final visual QA remain.
- C9 Word Cards is Windows-statically audited, but macOS compilation/XCTest plus device background/card/mascot composition, manual-versus-timed advance, continuous bags, long/multiword fit, English/Hebrew speech, VoiceOver/keyboard/Switch Control, mixed RTL/LTR, Dynamic Type, and final visual QA remain.
- The approved Math object/zero/grouping pack and native exact fraction bars, number lines, percent/ratio, probability, and geometry representations are integrated through M10. Xcode asset compilation plus device-scale visual, interaction, accessibility, and pedagogical QA remain incomplete.
- Firebase iOS records integration is implemented at source level for Minik Plus and English Only with the shared Android collections/public fields, anonymous-auth-gated transport, top-20 reads, atomic multi-record writes when both qualify, cache/error/configuration states, recoverable pending publication, and secure ownership that keeps `player_id` distinct from `auth.uid`. Each product/profile receives a persisted versioned UUID; `leaderboard_owners/{player_id}` contains only the private immutable `owner_uid`; one UID can own multiple profiles; legacy IDs cannot be claimed; and ownership is proven before write/delete. Local child names have no remote path, aliases/avatars remain curated, Parent can change the alias from generated choices, and deletion preserves local data. The isolated Language plists, Release App Attest, strict Rules/indexes, migration runbook, and Android file-level handoff exist. Strict deployment still requires the administrator archive/clear cutover and an updated Android release because legacy records have no Auth ownership and legacy Android accepts free-text `user_name`. Firebase Console/Auth/App Check actions, emulator/backend/device validation, final legal/retention wording, and live privacy publication remain incomplete.
- App Store policy/category/child privacy gate incomplete.

---

# PART X — DECISION LOG (APPEND ONLY)

Future ChatGPT/Codex sessions must append confirmed changes rather than rewriting history.

### 2026-08-30 — Product architecture correction

**Confirmed by user:**

- Android has no Math product; stop searching Android for Math curriculum.
- Math must reuse/parallel the richness of the existing activity families, not be reduced to seven generic engines.
- Math had been defined here with Tic-Tac-Toe as item 13; that item alone was explicitly superseded on 2026-08-31 by Ping Pong. The other twelve activity identities remain unchanged.
- Final Math quantity visuals use beautiful object art rather than generic dots.
- Higher values must use grouped/symbolic representations rather than hundreds of repeated objects.
- four-choice distractors must be plausible, unique, and include the correct answer exactly once.
- Math Soccer uses a fixed answer-ball pool with changing questions and the same educational/shot score matrix as Android Soccer.
- Math Tower builds a target count/value and uses extra available blocks plus a delayed stable-correct completion window.
- two Math simple construction activities replace the two Language first-letter-specific activities.
- Learn is instructional and separate from practice.
- the full app includes success animations, TTS, points/streaks/records, Firebase, Parent Area, progress, ads, remove-ads reminder/purchase, notifications, English Only, localization and App Store release work.
- App Store purchasing should be encapsulated in a separate reusable library for other applications.

### 2026-08-31 — Ping Pong, Math visual identity, and fourth product

**Confirmed by user:**

- Language Just-for-Fun remains Tic-Tac-Toe; Math Just-for-Fun is Ping Pong.
- Math still has 13 production activities, with Ping Pong replacing Tic-Tac-Toe as item 13; Ping Pong is outside Math curriculum/provider state.
- `MinikPingPong` is the fourth product and contains only the Ping Pong experience plus future shared monetization/code actions.
- Ping Pong has Starter/Easy/Medium/Hard, with Starter drag-to-ball and Tap/Swipe selection for Easy/Medium/Hard.
- Tap, Swipe, serves, legal bounce/net/out flight, incoming-shot-aware Minik AI, targets, scoring, service rotation, approved artwork mapping, persistence, accessibility, and lifecycle follow §7.13.
- `math_frame_background` is the centralized Minik Math practice frame; Language visuals remain unchanged and Ping Pong uses its arena.
- Ads/commerce/code redemption must remain shared host services; Ping Pong only exposes a narrow completed-match/action boundary and never fakes success.

### 2026-08-31 — Confirmed Math product, M1, progression, localization, and fit contracts

**Confirmed by user:**

- Level is WHAT is learned and activity is HOW it is practiced; all thirteen Math identities remain present at every level, with Ping Pong non-curriculum.
- The M1–M10 curriculum is the progression recorded in §8 and the matrix; Android is not Math curriculum authority.
- M1 spans 0...10 and numeral↔quantity/cardinality across twelve educational activities; Build Math is the ordered counting chain `1→...→N` and does not duplicate Build Number or Build Quantity.
- low-level Build Number uses draggable numeral tokens and no iOS keyboard; repeated future digits require distinct physical token IDs.
- Tower supports Count Tower for readable small answers and Answer Token Tower for larger/structured answers; M1 shows a numeral, always supplies extra blocks, uses explicit buzzer submission, supports correction and zero, has no completion countdown, and preserves speaker/replay behavior.
- zero quantity uses a neutral empty scene with no numeral answer leakage.
- Math Mixed excludes Learn/Cards/Ping Pong from graded child modes; Cards remains instructional/review with manual/shuffle/timed behavior.
- Math level mode defaults to Automatic; Manual never auto-changes. Starting calibration is three attempts with +2/+1/down tuning, normal promotion is 8 consecutive or 18/20 first-attempt correct, demotion is 7 consecutive failures or at most 8/20 correct, promotion probation is 6 attempts/4 failures, cooldown is 10 attempts, and time is only a family-specific secondary signal with >120 seconds recorded as very slow.
- automatic routing is clamped to implementation-ready levels; the child hub is not a level picker and future Parent Area owns Manual selection.
- activity progress application must be replay-idempotent and typed attempt data must carry stable identity, attempt index, result, duration, family, and optional Math level/skill without forcing Math fields into Language.
- every user-visible Swift string must be resource-localized before release. Supported interface locales are English, Amharic, Arabic, German, Spanish, French, Hebrew, Dutch, Brazilian Portuguese, European Portuguese, and Russian; English Only excludes Hebrew.
- mathematical content must never truncate. Fit uses a readable minimum, last-resort two-line layout, bounded 12-candidate regeneration, and a localized retry state rather than ellipsis or infinite loops.
- final M1 quantities require a separately generated/approved child-friendly object-art pack governed by the permanent requirements handoff; procedural dots/shapes remain development-only.

---

### 2026-09-06 — Owner requires complete Language Android reconstruction

The entire Language product and meaningful states must match all 16 binding Android references and actual source/assets, including discrepancies absent from owner annotations. This explicitly supersedes the tap-only Language Soccer adaptation: drag/aim/launch and physical outcomes are required, preserving the four-row educational-correctness × goal-result score contract. Native accessibility/safe areas cannot justify generic replacement compositions. No Math or English Only architecture change. Source implementation and real runtime verification are separate gates.

### 2026-09-13 — GitHub-hosted Simulator validation only

**Confirmed by user:**

- GitHub Actions is the only approved hosted Simulator validation service; Codemagic, Appetize, BrowserStack, Sauce Labs, and other external services are not used.
- The preferred workflow remains manual-only and every dispatch is a complete four-product gate, with one ProductConfigurationTests invocation after compile-clean builds.
- One GitHub-hosted modern iPhone Simulator must validate install, launch, stable initial rendering, screenshots, diagnostics, and clean termination for all built products before an aggregate verdict.
- The gate must preserve partial successful ZIP evidence, collect runtime evidence for review, require no signing or production-service credentials, and must not run the hosted AppStoreCommerceKit grace-period test.

---

### 2026-09-13 — Public leaderboard privacy model

**Confirmed by user:**

- Real/local child profile names remain local-only and must never be uploaded or used as the Firebase identity.
- Public leaderboard identity is an app-curated adjective + noun + number alias with an optional curated avatar; no free text, real-name field, photo, or initials-by-default path is permitted.
- The first eligible best score is celebrated and retained locally. It remains pending until one-time Parent approval; approval publishes it and permits later qualifying uploads without repeated approval.
- Parent Area owns persistent, grown-up-gated participation enable/disable and participant-record deletion. Disabling stops future uploads immediately, while deletion leaves local progress and records intact.
- Firebase anonymous authentication remains transport-only. The Android-compatible collections and legacy field names remain, but `user_name` contains only the generated public alias and the remote payload is restricted to opaque participant ID, public alias/avatar, score/streak, product/app ID, and timestamp.

---

### 2026-09-13 — Public leaderboard alias activation supersedes mandatory approval

**Confirmed by user:**

- Do not request a public alias during onboarding. The first leaderboard-qualifying score offers only curated generated aliases.
- Selecting an alias activates public leaderboard participation for that local profile and immediately attempts to publish the pending qualifying score. Future qualifying scores reuse the same selected alias.
- A separate persistent Parent approval is no longer required merely to select or use the curated alias. Parent Area retains direct, persistent Online leaderboard On/Off and participant-record deletion controls.
- No upload occurs before alias selection. A Parent opt-out stops future uploads and cannot be overridden by child alias selection; public-record deletion leaves local progress and local records intact.
- The local-name exclusion, no-free-text boundary, minimum remote field allowlist, and remaining owner/legal review gate are unchanged.

---

### 2026-09-13 — Canonical production Apple bundle identifiers

**Confirmed by user:**

- MinikPlus: `com.appsbybros.minik.plus`
- MinikPlusEnglish: `com.appsbybros.minik.plus.english`
- MinikMath: `com.appsbybros.minik.math`
- MinikPingPong: `com.appsbybros.minik.pingpong`
- ProductConfigurationTests: `com.appsbybros.minik.tests`
- These identifiers apply only to Apple/iOS configuration. Android application IDs remain unchanged, and the existing StoreKit product identifier remains `remove_ads`.

---

### 2026-09-14 — Secure multi-profile leaderboard ownership and legacy cutover

**Confirmed by user:**

- Firebase anonymous `auth.uid` is transport/ownership identity and must never replace the distinct opaque `player_id` for a local child profile; one Auth UID may own multiple profile IDs.
- Active clients use private `leaderboard_owners/{player_id}` bindings. Ownership is not publicly enumerable/displayed, another UID cannot transfer or use it, and public documents retain only the established Android-compatible fields.
- Historical UUIDs have no cryptographic owner and must never be claimed by a client based only on a public `player_id`. Updated profiles use new versioned opaque IDs and can republish retained local bests.
- The coordinated migration archives/verifies legacy public data, clears the active ranking during an administrator-controlled cutover, deploys strict ownership Rules, and moves both platforms to curated aliases without deleting local progress/rewards.
- App Check enforcement remains a separate later step after updated Apple and Android clients are registered, released, and healthy in metrics.

---


## 2026-09-28 — Modern Full/Simple and Apple Firebase registration

Owner decision: port the current standalone Android Modern Ping Pong to native iOS, including online/tournaments/ads and Apple purchases; provide a parameter selecting a simple house-player match that returns to its host when complete. Neither new entry point contains 80s. Do not change existing 80s gameplay or use the attached Pixels. The owner confirmed no Ping Pong Apple Firebase registration existed and instructed us to create the setup together. A dedicated Apple app was registered in existing `minikswish`; no production rules were deployed and no TripleShot paths were changed. The existing Math host is not rerouted as part of this Modern-only unit.

## 2026-09-28 — Shared Retro game, Math entries and local commits

Owner decision: commit the completed Modern work for the owner to push; bring current Android 80’s gameplay/UI/audio to iOS; keep both Modern and 80’s accessible from Math. Add a standalone 80’s entry with the same game/features and no feature-mode switch. Modern remains a shared Full/Simple implementation. Do not add ads to 80’s; existing Modern ads may remain, with a common library planned later. Android is read-only and attached Pixels remain off limits. A native WKWebView host reuses the current Android 80’s web payload to preserve its exact engine, assets and responsive behavior; host callbacks affect navigation only.

# PART XI — SPRINT LOG (APPEND AFTER EACH SPRINT)

Format:

```text
### YYYY-MM-DD — Sprint ID / Name
Status: completed / blocked / partial
Commit(s): ...
Files changed: ...
Tests run: ...
Mac validation: ...
Product decisions made by user: ...
Remaining blockers: ...
Master-plan sections updated: ...
Reviewer result: approved / corrections required
```

Do not erase prior sprint entries.

### 2026-08-30 — A0 / Canonical master plan repository integration
Status: completed
Commit(s): local checkpoint containing this entry, `docs: add canonical Minik master plan and UI references`
Files changed: `README.md`, `docs/MINIK_MASTER_PLAN.md`, and `docs/reference/android-ui/` (README plus 16 screenshots)
Tests run: complete document read; Git history/branch/status verification; project configuration, production catalog, Math prototype, and relevant Android-source audits; all 16 screenshots visually inspected; documentation diff checks
Mac validation: not applicable to documentation integration; A2 remains pending
Product decisions made by user: canonical product requirements supplied by the user were integrated without alteration
Remaining blockers: A1 branch convergence, A2 macOS/Xcode baseline, and the release blockers in §31
Master-plan sections updated: screenshot reference integration, repository snapshot, static-validation wording, Current Active Phase, Sprint Status, Sprint Log, and future-session bootstrap
Reviewer result: validated against the repository and reference material; no implementation started

### 2026-08-31 — P0 / Unified Ping Pong, Math identity, and fourth product
Status: implemented and statically reviewed on Windows; macOS validation pending
Commit(s): local checkpoint containing this entry, `checkpoint: add complete Minik Ping Pong game and product`
Files changed: Ping Pong models/session/flight/AI/preferences/host seam/SpriteKit scene/SwiftUI views; product configuration/root/catalog/hub/background/project configuration; isolated Ping Pong and Math asset catalogs; deterministic tests; this master plan
Tests run: `git diff --check`; asset inventory/visual inspection; asset-catalog JSON/name/resource-membership checks; structural searches and source review; deterministic XCTest source added but not executed because Swift/Xcode is unavailable on Windows
Mac validation: required for all four targets, XCTest, SpriteKit/SwiftUI runtime, assets, layout, accessibility, lifecycle, and difficulty tuning
Product decisions made by user: all dated decisions in the 2026-08-31 Decision Log entry
Remaining blockers: macOS validation/tuning; future shared Ads/commerce/code systems; the pre-existing release blockers in §31
Master-plan sections updated: product model, Math activity 13, complete Ping Pong contract, artwork/visual identity, current project/status, Definition of Done, roadmap, Living Status, Decision Log, Sprint Log
Reviewer result: pending user review and macOS validation

### 2026-08-31 — P0 correction / Ping Pong interaction and geometry hardening
Status: implemented and statically reviewed on Windows; macOS validation pending
Commit(s): local checkpoint containing this entry, `checkpoint: harden Ping Pong interaction and geometry`
Files changed: Ping Pong tuning/serve/AI rules, responsive table mapping, SpriteKit input/render mapping, deterministic tests, and this implementation-status entry
Tests run: `git diff --check`; asset/catalog revalidation; geometry/coupling structural searches; deterministic XCTest coverage added but not executed because Swift/Xcode is unavailable on Windows
Mac validation: required for all four targets, XCTest, visual table alignment on iPhone/iPad portrait and landscape, touch behavior, SpriteKit flight, accessibility, lifecycle, and final difficulty tuning
Product decisions made by user: none beyond the existing Ping Pong contract; this checkpoint corrects implementation fidelity findings
Remaining blockers: macOS validation/tuning; future shared Ads/commerce/code systems; the pre-existing release blockers in §31
Master-plan sections updated: current Ping Pong implementation status and Sprint Log only
Reviewer result: pending user review and macOS validation

### 2026-08-31 — B1 / Math production activity identity model
Status: implemented and statically reviewed on Windows; macOS validation pending
Commit(s): `7075c8a` (`checkpoint: model 13 Math production activities`)
Files changed: canonical Math production identity/readiness/route model, product-level Math catalog and hub routing, typed catalog/identity tests, and this status entry
Tests run: complete diff inspection; `git diff --check`; static symbol/routing searches; deterministic XCTest source added but not executed because Swift/Xcode is unavailable on Windows
Mac validation: required for all targets and ProductConfigurationTests
Product decisions made by user: none; unfinished identities retain blocked/planned status and do not inherit unrelated engines
Remaining blockers: activity-specific product definitions/content, full 10×13 matrix approval, and macOS validation
Master-plan sections updated: Current Active Phase, Sprint Status, release blockers, and Sprint Log
Reviewer result: pending user review and macOS validation

### 2026-08-31 — E1–E12 / Canonical Math production matrix
Status: completed as an architecture/status inventory; curriculum approval remains pending
Commit(s): `1149b94` (`checkpoint: add canonical Math production matrix`)
Files changed: `docs/math-production-matrix.md` and this master-plan link/status/log entry
Tests run: 130-cell count and 13-cells-per-level structural validation; status-vocabulary validation; `git diff --check`; complete documentation diff inspection
Mac validation: not applicable to the document itself; all implementation remains subject to the macOS gate
Product decisions made by user: none; unapproved ranges, representations, policies, and interactions are explicitly open
Remaining blockers: the five consolidated decision groups at the top of the matrix and activity implementation
Master-plan sections updated: Math curriculum link, Current Active Phase, Sprint Status, release blockers, and Sprint Log
Reviewer result: pending user review

### 2026-08-31 — F1 / Math semantic representation foundation
Status: implemented and statically reviewed on Windows; macOS validation pending
Commit(s): `1c5e2b4` (`checkpoint: add Math semantic representation foundation`)
Files changed: typed Math representation families, exact numeric-equivalence semantics, generic rendering/direction support, deterministic contract tests, and this status entry
Tests run: complete diff inspection; `git diff --check`; exhaustive representation-switch search; deterministic XCTest source added but not executed because Swift/Xcode is unavailable on Windows
Mac validation: required for all targets, ProductConfigurationTests, SwiftUI rendering, RTL behavior, and accessibility output
Product decisions made by user: none; the foundation models capabilities but does not assign level thresholds, ranges, or exercise policy
Remaining blockers: final Math object art, quantity layout, distractor policy, curriculum approvals in the matrix, and macOS validation
Master-plan sections updated: Current Active Phase, Sprint Status, and Sprint Log
Reviewer result: pending user review and macOS validation

### 2026-08-31 — F2 / Math quantity layout and object-theme foundation
Status: implemented and statically reviewed on Windows; final object art and macOS validation pending
Commit(s): `c826867` (`checkpoint: add Math quantity layout foundation`)
Files changed: pure deterministic quantity layout, typed object-theme/asset manifest seam, adaptive SwiftUI quantity renderer, representation integration, deterministic tests, and this status entry
Tests run: complete diff inspection; `git diff --check`; structural source checks; deterministic XCTest source for zero/one/several/narrow/wide/grouped/bounds/no-overlap/manifest cases added but not executed because Swift/Xcode is unavailable on Windows
Mac validation: required for all targets, ProductConfigurationTests, SwiftUI layout on iPhone/iPad, accessibility, and final asset rendering
Product decisions made by user: none; grouping is caller-selected and no curriculum threshold or final art pack was chosen
Remaining blockers: approved final object artwork/empty-state art, curriculum-controlled quantity/grouping thresholds, distractor infrastructure, and macOS validation
Master-plan sections updated: Current Active Phase, Sprint Status, and Sprint Log
Reviewer result: pending user review and macOS validation

### 2026-08-31 — F3 / Deterministic Math distractor engine
Status: implemented and statically reviewed on Windows; curriculum policy integration and macOS validation pending
Commit(s): `d4192fd` (`checkpoint: add Math distractor engine`)
Files changed: context/domain-driven distractor generator, seeded RNG, typed generation failure, deterministic tests, and this status entry
Tests run: complete diff inspection; `git diff --check`; structural source checks; deterministic XCTest source for uniqueness, exact-once correctness, seeds, duplicate collapse, insufficient candidates, overflow edges, and caller policy added but not executed because Swift/Xcode is unavailable on Windows
Mac validation: required for ProductConfigurationTests and future provider integrations
Product decisions made by user: none; the engine exposes strategies but only caller-approved curriculum policy may activate them
Remaining blockers: approved per-cell distractor policies in the Math matrix, provider integration, final object art, and macOS validation
Master-plan sections updated: Current Active Phase, Sprint Status, and Sprint Log
Reviewer result: pending user review and macOS validation

### 2026-08-31 — B4 / Shared local activity progress foundation
Status: implemented and statically reviewed on Windows; activity rollout and macOS validation pending
Commit(s): `09a3d3d` (`checkpoint: add shared local progress foundation`)
Files changed: typed shared activity events/contexts, progress reducer/repository protocols, versioned UserDefaults repository, Codable ID support, deterministic tests, integration plan, and this status entry
Tests run: complete diff inspection; `git diff --check`; structural source checks; deterministic XCTest source for Codable round trips, aggregation, persistence, product isolation, Ping Pong match semantics, and duration validation added but not executed because Swift/Xcode is unavailable on Windows
Mac validation: required for ProductConfigurationTests and each incremental activity integration
Product decisions made by user: none; optional curriculum/skill fields preserve product separation and no Firebase/profile/sync policy was chosen
Remaining blockers: incremental activity emission wiring, duplicate-event/idempotency policy at backend sync, profile ownership, progress UI, rewards, and macOS validation
Master-plan sections updated: Current Active Phase, Sprint Status, Sprint Log; `docs/activity-event-integration-plan.md` added
Reviewer result: pending user review and macOS validation

### 2026-08-31 — B5 / Shared rewards and streak foundation
Status: implemented and statically reviewed on Windows; product-policy integration and macOS validation pending
Commit(s): `f9a385f` (`checkpoint: add shared rewards and streak foundation`)
Files changed: pure reward state/policy/processor, typed reward events/results, versioned idempotent local ledger, records protocol seam, deterministic tests, Android behavior reference, and this status entry
Tests run: Android reward/persistence source inspection; complete iOS diff inspection; `git diff --check`; structural source checks; deterministic XCTest source for tiers, point floor, streak/best behavior, game policy, persistence/idempotency, scope isolation, Ping Pong boundary, and unconfigured reasons added but not executed because Swift/Xcode is unavailable on Windows
Mac validation: required for ProductConfigurationTests and each later activity/product integration
Product decisions made by user: none; activity-specific Android rules are documented/reference-configured but not silently applied to Math or Ping Pong
Remaining blockers: final Language/Math/Ping Pong reward policies, profile ownership, activity event-to-reward wiring, backend records adapter/UI, and macOS validation
Master-plan sections updated: Current Active Phase, Sprint Status, Sprint Log; `docs/android-reward-reference.md` added
Reviewer result: pending user review and macOS validation

### 2026-08-31 — Unit 8 / Math and shared-foundation consolidation
Status: completed and statically reviewed on Windows; macOS validation pending
Commit(s): `checkpoint: consolidate Math and shared foundations` (exact hash reported at sprint handoff)
Files changed: this Living Status/Sprint Log consolidation only
Tests run: checkpoint history/status/index audit; sprint file inventory; Android/Phase 41 preservation checks; `git diff --check`; complete staged documentation diff inspection
Mac validation: A2 Foundation Validation Gate is the exact next recommended sprint
Product decisions made by user: none
Remaining blockers: §30 open decisions; final Math object art; approved curriculum/distractor/reward policies; incremental event/reward integration; profile/backend/UI work; macOS compilation/tests/runtime validation
Master-plan sections updated: Current Active Phase, exact next sprint, checkpoint hashes, and Sprint Log
Reviewer result: pending user review and macOS validation

### 2026-09-01 — B4 correction / Replay-safe typed attempts
Status: completed and statically reviewed on Windows; macOS validation pending
Commit(s): `0d56c1b` (`checkpoint: make activity progress replay safe`)
Files changed: typed attempt/event contracts, replay-idempotent progress snapshots/repository compatibility, Math level Codable identity, and deterministic progress tests
Tests run: staged diff inspection; `git diff --cached --check`; deterministic XCTest source for replay, real retry, first-attempt semantics, duration validation, Language optionality, and non-curriculum Ping Pong added but not executed
Mac validation: ProductConfigurationTests remain required
Product decisions made by user: typed minimum attempt fields and replay idempotency recorded in the 2026-08-31 Decision Log entry
Remaining blockers: macOS compile/XCTest and future backend synchronization
Master-plan sections updated: telemetry contract, Living Status, Decision Log, and this Sprint Log
Reviewer result: static review complete; macOS validation pending

### 2026-09-01 — Automatic level and Math presentation-fit foundations
Status: completed and statically reviewed on Windows; macOS validation pending
Commit(s): `5f65ce4` (`checkpoint: add automatic math level foundation`); `9eb8cec` (`checkpoint: prevent math presentation truncation`)
Files changed: pure automatic-level state/controller/persistence and tests; shared bounded Math fit policy, non-truncating rendering, and tests
Tests run: complete staged diff inspections; `git diff --cached --check`; deterministic XCTest source added for calibration, promotion/demotion, probation/cooldown, Manual behavior, M1 readiness clamp, 12-attempt bounds, minimum size, long values, multiline fallback, and failure
Mac validation: ProductConfigurationTests and SwiftUI rendering remain required
Product decisions made by user: automatic/manual semantics, starting thresholds, time policy, readiness clamp, and never-truncate contract recorded in Decision Log
Remaining blockers: Parent Area UI, future ready-level expansion, activity-specific fit adoption, and macOS validation
Master-plan sections updated: progression, presentation/accessibility, Living Status, Decision Log, and this Sprint Log
Reviewer result: static review complete; macOS validation pending

### 2026-09-01 — M1 / Functional twelve-activity Math slice
Status: functionally implemented and statically reviewed on Windows; not release-complete
Commit(s): `c142411` (`checkpoint: complete functional M1 math slice`); `5de238b` (`docs: record confirmed M1 math product`); `66b526f` (`checkpoint: correct M1 retry timing`); final status checkpoint containing this update
Files changed: dedicated M1 provider/factory/router/views, construction session and buzzer, shared activity telemetry hooks, interface-language speech, Cards shuffle/timed flow, localization catalogs/validation/audit scripts, product routing/tests, Math art handoff, canonical plan, and matrix
Tests run: `git diff --check`; complete staged diff reviews; String Catalog JSON/locale validation (29 keys, 11 full locales, 10 English Only locales); cross-catalog consistency/Hebrew-exclusion audit; hardcoded-literal audit (177 remaining); 130-cell/13-per-level matrix audit; structural searches; deterministic XCTest source added but not executed
Mac validation: required for all four targets, ProductConfigurationTests, all twelve M1 activities, drag/drop, speech, accessibility, RTL, Dynamic Type, Reduce Motion, layouts, lifecycle, and resource compilation
Product decisions made by user: all decisions in the 2026-08-31 Math product/M1/progression/localization/fit Decision Log entry
Remaining blockers: final approved object/container/block art, native-language translation QA, 177 legacy localization candidates, macOS/Xcode/Simulator validation, and M2–M10 production implementation
Master-plan sections updated: Build/Mixed/Cards/Tower contracts, curriculum/progression, localization, art, fit, current status, roadmap board, decisions, blockers, bootstrap, and Sprint Log; full matrix updated
Reviewer result: static review complete after correcting a Language-target factory regression, shifted localization mappings, and per-retry response-duration boundaries; macOS validation pending

### 2026-09-01 — M1 corrections, localization closure, and functional M2 slice
Status: functionally implemented and statically reviewed on Windows; not release-complete
Commit(s): `2ae6b26` (`checkpoint: localize current Minik interface copy`); `b95a847` (`checkpoint: complete functional M2 math slice`); documentation checkpoint containing this entry
Files changed: Build Number drag-primary presentation, typed interface locale/persistence/environment, explicit hosting-locale speech, complete String Catalog migration/audit, mechanic-specific fit gate, dedicated M2 provider/factory/router/views/tests, M1/M2 telemetry level plumbing, shared outcome-dispatch boundary, matrix and Living Status
Tests run: localization hardcoded/key/locale/key-parity audit; String Catalog JSON/locale validation; 130-cell matrix audit; `git diff --check`; structural searches for M1 hardcoding, device-locale speech, truncation, M2 regressions, readiness, Language Tower, and Ping Pong changes; deterministic XCTest source added but not executed on Windows
Mac validation: required for all four targets, all ProductConfigurationTests, M1/M2 activities, SwiftUI drag/drop, speech, accessibility, RTL, Dynamic Type, Reduce Motion, fit behavior, resources, and lifecycle
Product decisions made by user: M2 WHAT/ranges/activity contracts, Build Number drag-primary behavior, selected interface-language policy, operational fit gate, and M2 readiness expansion supplied in the sprint brief
Remaining blockers: final approved Math object/container/block art, native-language review for `needs_review` catalog entries, macOS/Xcode/Simulator validation, Parent Area UI, approved Math reward values, and coherent M3–M10 production slices
Reviewer result: Windows static review complete; macOS compile/test and interaction review pending

### 2026-09-02 — Approved Math artwork and functional M3 slice
Status: functionally implemented and statically reviewed on Windows; not release-complete
Commit(s): `61090b7` (`checkpoint: integrate approved Math object artwork`); `aa89faf` (`checkpoint: apply Math object artwork to M1 and M2`); `b7b243d` (`checkpoint: complete functional M3 math slice`); documentation checkpoint containing this entry
Files changed: dedicated 109-image Math catalog and manifest, asset validation/typed registry/theme selector, production M1/M2 quantity/zero/grouping presentation, dedicated M3 provider/factory/router/views/tests, M3 progression readiness, and durable status documents
Tests run: 109-set manifest/catalog/file validation; 100-object/ten-category/three-zero/six-grouping counts; localization hardcoded/key/locale audit; 130-cell matrix audit; `git diff --check`; structural searches for fit bounding, M3 level metadata, production Tower routing, Ping Pong and Language Tower changes; deterministic XCTest source added but not executed on Windows
Mac validation: required for all targets and ProductConfigurationTests, asset-catalog compilation, all M1/M2/M3 activity-level combinations, visual scale/contrast, zero/grouped art, drag/drop, speech, accessibility, RTL, Dynamic Type, Reduce Motion, fit behavior, and lifecycle
Product decisions made by user: the staging pack is approved for Math production; M3 0...20 missing-value/equivalent-expression contracts and readiness expansion were supplied in the sprint brief
Remaining blockers: macOS/Xcode/Simulator gate, native-language review for `needs_review` entries, higher-level representation art, Parent Area UI, approved Math reward values, and coherent M4–M10 production slices
Reviewer result: Windows static review complete; M4 intentionally not started because a complete twelve-identity slice could not be safely completed within the remaining capacity

### 2026-09-02 — Functional M4 and M5 Math slices
Status: functionally implemented and statically reviewed on Windows; not release-complete
Commit(s): `01c2834` (`checkpoint: complete functional M4 math slice`); `1f44f7b` (`checkpoint: complete functional M5 math slice`); documentation checkpoint containing this entry
Files changed: dedicated M4/M5 providers, factories, routes, views and tests; typed place-value/equal-group rendering; structure-sensitive construction; dual-mode Tower; readiness/progression; matrix, art, localization, and status documents
Tests run: localization hardcoded/key/catalog/locale audit; Math manifest/catalog/file validation; 130-cell matrix structure audit; bounded fit and activity-route structural searches; brace/source review; `git diff --check`; deterministic XCTest source added but not executed because Swift/Xcode is unavailable on Windows
Mac validation: required for all four products, ProductConfigurationTests, M1–M5 SwiftUI rendering/interaction, asset compilation, speech, accessibility, RTL, Dynamic Type, Reduce Motion, fit behavior, and lifecycle
Product decisions made by user: the M4 and M5 WHAT, ranges, representation policies, activity contracts, Tower split, and readiness expansion were supplied in the sprint brief
Remaining blockers: Codemagic/macOS compile-test gate, native-language review for 257 fallback entries per non-English locale, M6–M10, Parent Area, approved reward values, and post-M5 representation art
Master-plan sections updated: automatic-ready set, Current Active Phase, exact next sprint, status board, release blockers, Sprint Log; M4/M5 matrix and art/localization status updated
Reviewer result: Windows static review complete; M6 intentionally not started because a complete twelve-identity slice would not fit safely in the remaining capacity

### 2026-09-02 — Windows-accessible iOS Simulator pipeline
Status: configured and statically reviewed on Windows; first hosted macOS run pending
Commit(s): documentation/pipeline checkpoint containing this entry, `checkpoint: add Windows-accessible iOS simulator build pipeline`
Files changed: `codemagic.yaml`, Windows/Appetize handoff guide, localization QA status, Math status documents, and this Sprint Log
Tests run: workflow/script structural inspection; exact artifact-name audit; failure-propagation search; `git diff --check`; local YAML parser unavailable on Windows
Mac validation: the configured Codemagic workflow will generate the project, run ProductConfigurationTests on a dynamically selected iPhone Simulator, and build/package all four unsigned Simulator apps
Product decisions made by user: Codemagic macOS/Xcode, unsigned Simulator products, exact four artifacts, and Appetize-on-Windows handoff were supplied in the sprint brief
Remaining blockers: first Codemagic execution and correction pass; physical-device/TestFlight testing remains a later gate
Master-plan sections updated: Current Active Phase, exact next sprint, blockers, and Sprint Log
Reviewer result: static review complete; hosted macOS execution pending

### 2026-09-02 — Functional M6 Math slice
Status: functionally implemented and statically reviewed on Windows; not release-complete
Commit(s): local checkpoint containing this entry, `checkpoint: complete functional M6 math slice`
Files changed: dedicated M6 provider/factory/router/view/tests; typed factor/multiple/fraction skills; native fraction-bar rendering and construction; shared no-truncation correction; readiness/progression; matrix, art and localization status
Tests run: localization hardcoded/key/catalog audit; Math manifest/catalog validation; 130-cell matrix audit; bounded fit/readiness/routing/regression searches; complete source/staged-diff inspection; deterministic XCTest source added but not executed because Swift/Xcode is unavailable on Windows
Mac validation: required for all four products, ProductConfigurationTests, M1–M6 rendering/interaction, fraction bars, assets, speech, accessibility, RTL, Dynamic Type, Reduce Motion, fit behavior, and lifecycle
Product decisions made by user: M6 fluency/factor/multiple/half-quarter scope and all activity contracts were supplied in the sprint brief
Remaining blockers: first Codemagic compile/XCTest result, native-language QA, complete M7–M10 slices, and later release systems
Master-plan sections updated: automatic-ready set, Current Active Phase, exact next level, status board, release blockers, Sprint Log; M6 matrix and art/localization status updated
Reviewer result: Windows static review complete; M7 intentionally not started because the remaining capacity could not support all twelve identities without partial production work

### 2026-09-02 — Functional M7 Math slice
Status: functionally implemented and statically reviewed on Windows; not release-complete
Commit(s): local checkpoint containing this entry, `checkpoint: complete functional M7 math slice`
Files changed: dedicated M7 provider/factory/router/view/tests; exact fraction/decimal skills; native number-line rendering; readiness/progression; matrix, art and localization status
Tests run: localization/catalog/Math asset/matrix audits; exact rational equivalence, bounded fit, readiness and progression source tests added; complete diff review; XCTest not executed because Swift/Xcode is unavailable on Windows
Mac validation: required for ProductConfigurationTests and all four products, including M7 fraction/decimal rendering, interaction, speech, accessibility, RTL, Dynamic Type and fit behavior
Remaining blockers: concrete Codemagic compile/XCTest result, native-language QA, complete M8–M10 slices, Parent Area and later release systems
Reviewer result: Windows static review complete; M8 intentionally not started because remaining capacity cannot support a coherent twelve-identity slice

### 2026-09-02 — Functional M8 Math slice
Status: functionally implemented and statically reviewed on Windows; not release-complete
Commit(s): local checkpoint containing this entry, `checkpoint: complete functional M8 math slice`
Files changed: dedicated M8 provider/factory/router/view/tests; exact fraction/decimal/percent/ratio semantics; native percent-bar and ratio-group rendering; proportional construction; readiness/progression; matrix and localization status
Tests run: localization/catalog/Math asset/matrix audits; exact rational equivalence, malformed token ordering, bounded fit, readiness, routing and progression source tests added; complete diff review; XCTest not executed because Swift/Xcode is unavailable on Windows
Mac validation: required for ProductConfigurationTests and all four products, including M8 percent/ratio rendering, interaction, speech, accessibility, RTL, Dynamic Type and fit behavior
Product decisions made by user: M8 fraction/decimal/percent/ratio relationship scope and all activity contracts were supplied in the sprint brief
Remaining blockers: concrete Codemagic compile/XCTest result, native-language QA, complete M9–M10 slices, Parent Area and later release systems
Master-plan sections updated: automatic-ready set, Current Active Phase, exact next level, status board, release blockers and Sprint Log; M8 matrix/localization status updated
Reviewer result: Windows static review complete; macOS compile/test and interaction review pending

### 2026-09-02 — Functional M9 Math slice
Status: functionally implemented and statically reviewed on Windows; not release-complete
Commit(s): local checkpoint containing this entry, `checkpoint: complete functional M9 math slice`
Files changed: dedicated M9 provider/factory/router/view/tests; validated typed signed-number/order-of-operations/power/ratio/equation representations; native bounded signed-number-line construction; readiness/progression; matrix and localization status
Tests run: localization/catalog/Math asset/matrix audits; exact rational equivalence, invalid-model rejection, malformed token ordering, bounded fit, number-line retry/bounds, readiness, routing and progression source tests added; complete diff review; XCTest not executed because Swift/Xcode is unavailable on Windows
Mac validation: required for ProductConfigurationTests and all four products, including M9 symbolic/number-line rendering, interaction, speech, accessibility, RTL, Dynamic Type and fit behavior
Product decisions made by user: M9 negative-number/order-of-operations/powers/ratios/one-step-equation scope and all activity contracts were supplied in the sprint brief
Remaining blockers: concrete Codemagic compile/XCTest result, native-language QA, complete M10 slice, Parent Area and later release systems
Master-plan sections updated: automatic-ready set, Current Active Phase, exact next level, status board, release blockers and Sprint Log; M9 matrix/localization status updated
Reviewer result: Windows static review complete; macOS compile/test and interaction review pending

### 2026-09-02 — Functional M10 Math slice
Status: functionally implemented and statically reviewed on Windows; not release-complete
Commit(s): local checkpoint containing this entry, `checkpoint: complete functional M10 math slice`
Files changed: dedicated M10 provider/factory/router/view/tests; validated typed two-step-equation/linear/proportion/probability/geometry representations; native probability and rectangle diagrams; exact probability construction; all-level readiness/progression; matrix and localization status
Tests run: localization/catalog/Math asset/matrix audits; exact rational equivalence, invalid-model rejection, malformed token ordering, bounded fit, readiness upper-bound/probation/routing source tests added; complete diff review; XCTest not executed because Swift/Xcode is unavailable on Windows
Mac validation: required for ProductConfigurationTests and all four products, including M10 symbolic/diagram rendering, interaction, speech, accessibility, RTL, Dynamic Type and fit behavior
Product decisions made by user: M10 equation/linear/proportional/probability/geometry scope and all activity contracts were supplied in the sprint brief
Remaining blockers: concrete Codemagic compile/XCTest result, native-language QA, cross-level core audit, Parent Area and later release systems
Master-plan sections updated: all-level Automatic readiness, Current Active Phase, next audit, status board, release blockers and Sprint Log; M10 matrix/localization status updated
Reviewer result: Windows static review complete; macOS compile/test and interaction review pending

### 2026-09-02 — Math educational-core cross-level audit
Status: `MATH_EDUCATIONAL_CORE_FUNCTIONAL_WINDOWS_STATIC_COMPLETE`; explicitly not release-ready
Commit(s): local checkpoint containing this entry, `checkpoint: record Math educational core static milestone`
Files changed: dedicated audit evidence plus master-plan and matrix milestone references
Tests run: 10 provider/factory/view/test-stack existence checks; 13-case factory checks; 10 dedicated-route, 10 implemented-level and 10 ready-level checks; 130 total/120 educational/10 Ping Pong/zero-TBD matrix audit; localization 0/0/0; 286-key 11/10-locale catalog validation; zero-error Math asset validation; `git diff --check`
Mac validation: not available; all Xcode/XCTest/Simulator/device gates remain required
Remaining blockers: concrete compile/XCTest results, native-language QA, visual/content tuning, Parent Area/progress, commercial/privacy/backend systems, and release operations
Reviewer result: cross-level Windows static audit passed with zero structural errors; no correction checkpoint required

### 2026-09-02 — H3 local slice / Educational Parent Area
Status: implemented and statically reviewed on Windows; macOS interaction validation pending
Commit(s): `55b9ff4` (`checkpoint: add educational Parent Area`)
Files changed: shared educational Parent Area/settings policy and SwiftUI surface; learned-language and encouragement persistence; shared root/hub integration; locale display names and 11/10-locale catalog entries; deterministic policy/state tests; this status entry
Tests run: Parent policy/state XCTest source added for product eligibility, learned-language policy/persistence, encouragement persistence, interface-locale policy, Manual immutability, and mode transitions; localization hardcoded/key/catalog audit 0/0/0; String Catalog JSON and 320-key 11/10-locale validation; complete diff/static source review; XCTest not executed because Swift/Xcode is unavailable on Windows
Mac validation: required for all three educational products, ProductConfigurationTests, navigation, pickers, persistence, interface-language speech, Dynamic Type, VoiceOver, RTL, iPhone/iPad layout, and resource compilation
Product decisions made by user: the ordered Parent Area product/mode/language/encouragement/progress-entry requirements were supplied in the sprint brief; no gate or notification cadence was invented
Remaining blockers: local Progress / Statistics UI, safe local records/streak presentation, commerce/legal controls, any future confirmed policy gate, native-language QA, and macOS validation
Master-plan sections updated: Current Active Phase, exact next sprint, status board, release blockers, and Sprint Log
Reviewer result: Windows static review complete; macOS compile/test and interaction review pending

### 2026-09-02 — B9/H4 local slice / Educational Progress and Statistics
Status: implemented and statically reviewed on Windows; specialized Language telemetry and macOS validation pending
Commit(s): `569355a` (`checkpoint: add local educational progress and statistics`)
Files changed: deterministic educational progress read model and SwiftUI surface; exact Math production-activity recording; typed Language choice/build/pairs/memory/Mixed recording; shared attempt-family extension; localized 11/10-locale catalog entries; deterministic read-model tests; Parent route integration; this status entry
Tests run: XCTest source added for empty state, one attempt, multiple activities, retry/first-attempt semantics, replay idempotency, product-isolated time aggregation, Math level/mode, mastery exclusions, and deterministic recent/row ordering; localization hardcoded/key/catalog audit 0/0/0; 340-key 11/10-locale catalog validation; complete diff/static source review; XCTest not executed because Swift/Xcode is unavailable on Windows
Mac validation: required for all educational products, ProductConfigurationTests, local persistence refresh, duration/date/percent formatting, Dynamic Type, VoiceOver, RTL, iPhone/iPad layout, and resource compilation
Product decisions made by user: metrics, first-attempt semantics, exclusions, device-local truthfulness, and repository/read-model requirements were supplied in the sprint brief
Remaining blockers: specialized Language Soccer/Tower typed telemetry, local reward-record presentation, backend sync, native-language QA, and macOS validation
Master-plan sections updated: Current Active Phase, exact next sprint, status board, release blockers, and Sprint Log
Reviewer result: Windows static review complete; macOS compile/test and interaction review pending

### 2026-09-02 — B5/H4 local slice / Records and Streaks shell
Status: implemented and statically reviewed on Windows; production reward integration and macOS validation pending
Commit(s): `1abc72e` (`checkpoint: add local records and streaks shell`)
Files changed: deterministic product-and-owner-scoped reward-ledger read model; accessible local Records / Streaks view and honest empty state; Parent Area route; localized 11/10-locale catalog entries; read-model tests; this status entry
Tests run: XCTest source added for empty, exact stored-state, product isolation, and owner isolation behavior; localization and catalog validation; complete diff/static source review; XCTest not executed because Swift/Xcode is unavailable on Windows
Mac validation: required for all educational products, ProductConfigurationTests, local ledger loading, Dynamic Type, VoiceOver, RTL, iPhone/iPad layout, and resource compilation
Product decisions made by user: expose only safely supported local records/streak values and do not invent Math point values
Remaining blockers: production reward event wiring/policies, backend records, specialized Language telemetry, native-language QA, and macOS validation
Master-plan sections updated: Current Active Phase, exact next sprint, status board, release blockers, and Sprint Log
Reviewer result: Windows static review complete; macOS compile/test and interaction review pending

### 2026-09-02 — A2/N2 validation slice / Manual GitHub iOS pipeline
Status: implemented and statically audited on Windows; first manual GitHub-hosted macOS run pending
Commit(s): `960cace` (`checkpoint: add manual GitHub iOS validation pipeline`)
Files changed: manual-only GitHub Actions workflow; deterministic workflow audit; Windows/GitHub/Appetize operator guide; this status entry
Tests run: workflow static audit verifies workflow_dispatch-only triggering, false-by-default single XCTest command, product selection, all four schemes and ZIP names, unsigned builds, deterministic DerivedData/app paths, ditto packaging, five three-day artifact uploads, no cache action, no DerivedData upload, and no hidden `|| true`; complete diff/static source review
Mac validation: not run in this sprint; the first user-started run must use `run_tests=true` and `product=all`
Product decisions made by user: GitHub-hosted macOS, manual-only execution, inputs/defaults, four products, single test pass, unsigned Simulator packaging, three-day retention, and Appetize handoff were supplied in the sprint brief
Remaining blockers: first manual workflow execution and correction pass; physical-device/TestFlight validation remains a later gate
Master-plan sections updated: Current Active Phase, exact next sprint, A2 status, release blockers, and Sprint Log
Reviewer result: Windows static audit complete; GitHub Actions syntax/execution and Xcode build/test results pending

### 2026-09-02 — A2 usage correction / All GitHub macOS workflows manual-only
Status: implemented and statically audited; remote run-log failure detail remains unavailable in this environment
Commit(s): `5b64a3a` (`checkpoint: make GitHub iOS validation manual only`)
Files changed: removed only `push` and `pull_request` from the pre-existing **iOS CI** trigger; expanded the workflow audit to reject automatic triggers in every current workflow file
Tests run: all four workflow files read completely; directory-wide trigger audit reports zero automatic-trigger errors; simulator workflow input/test/product/artifact/retention contract remains green; staged diff and status reviewed
Remote diagnosis: run/job ID `91194820829` returned 404 through unauthenticated and available stored-credential API access, and GitHub CLI is not installed, so no compiler/test-log cause is claimed
Preserved work: Phase 41 benchmark workflow and benchmark implementation were not staged or altered by this checkpoint
Remaining blocker: obtain the failed run log from an account with repository Actions access before making any build/project correction attributed to that run
Reviewer result: automatic quota consumption from current workflow triggers is prevented once this checkpoint is pushed; no remote workflow was triggered, rerun, canceled, or otherwise mutated

### 2026-09-03 — A2 correction / Apple XML compilation and quota-efficient manual validation
Status: corrected and statically audited on Windows; clean macOS execution pending
Commit(s): `8eac5e6` (`checkpoint: fix Apple Foundation XML compilation`); `97dff38` (`checkpoint: harden manual GitHub iOS validation`)
Files changed: portable Foundation XML import; preferred manual Simulator build/test ordering, aggregate four-product compile reporting, universal Simulator setting and DerivedData reuse; workflow-directory trigger audit; completion estimate and blocker status
Tests run: all four `.github/workflows/*.yml` files read completely; directory audit also discovers `.yaml`; every top-level `on:` mapping permits only `workflow_dispatch`; preferred workflow audit reports one test command, five three-day uploads, one macOS job, all four exact ZIP paths, aggregate exit-status handling, and zero trigger errors; localization source/key/catalog audit 0/0/0; 350-key 11/10-locale catalogs valid; Math asset audit 0 errors with 100 objects, 3 zero states, 6 grouping assets and 10 categories; `git diff --check`; Xcode unavailable on Windows
Mac validation: reviewer-supplied run `91194820829` showed XcodeGen success followed by MinikPlus compile failure `unable to resolve module dependency: 'FoundationXML'`; the portable import correction is not yet rerun on macOS
Product decisions made by user: all GitHub workflows are manual-only; the preferred workflow uses one paid job to attempt all requested builds before one optional test run
Remaining blockers: deliberate user-started `run_tests=true`, `product=all` validation; physical-device/TestFlight, linguistic, visual, accessibility, commerce, backend, privacy and release gates
Master-plan sections updated: completion estimate, Current Active Phase, release blockers, and Sprint Log
Reviewer result: source/workflow correction prepared for review; macOS confirmation pending

### 2026-09-03 — B4/B9 Language Soccer and Tower typed telemetry
Status: implemented and statically reviewed on Windows; macOS interaction validation pending
Commit(s): telemetry checkpoint containing this entry
Files changed: shared ordered-token attempt tracker and deterministic tests; Language Soccer/Tower attempt emission; educational hub progress wiring; Living Status
Tests run: Android Soccer/Tower correctness and per-word outcome behavior inspected read-only; deterministic XCTest source covers retry index, token/content reset, stable challenge identity, Soccer/Tower family, duration validation, and absent Math fields; localization, catalog, Math asset, workflow and diff audits rerun on Windows; XCTest not executed because Swift/Xcode is unavailable on Windows
Mac validation: required for both Language products, ProductConfigurationTests, Soccer kicks/shot cancellation, Tower drag/accessibility placement, speech/replay, retry timing, persistence and progress refresh
Product decisions made by user: none; current Language behavior and existing typed progress contracts remain authoritative
Remaining blockers: deliberate full manual macOS run, remaining Language deep release audits, final reward/backend integration, native-language QA, visual/device QA and release systems
Master-plan sections updated: Current Active Phase, exact next action, status board, release blockers, and Sprint Log
Reviewer result: Windows static review complete; macOS compile/test and interaction confirmation pending

### 2026-09-03 — Independent-review correction / Localization, accessibility, telemetry identity, and build logs
Status: corrected and statically audited on Windows; macOS validation pending
Commit(s): correction checkpoint containing this entry, `checkpoint: fix independent review findings`
Files changed: explicit localization boundaries for dynamic user-facing String paths; 11/10-locale fallback catalog entries; strengthened localization audit; Manual/Automatic Math hub accessibility; presentation-aware Language ordered-token attempt tracking and tests; failure-safe Simulator build-log artifact and workflow audit; Windows testing guide; this status entry
Tests run: localization direct-literal/dynamic-boundary/key/catalog audit 0/0/0/0; String Catalog validation 462 keys with 11 full and 10 English Only locales; all four workflow files directly inspected and directory audit reports workflow_dispatch-only triggers, one test command, six three-day uploads, and zero automatic-trigger errors; deterministic XCTest cases authored for repeated semantic tokens across presentations and invalid presentation IDs but not executed because Swift/Xcode is unavailable on Windows
Mac validation: required for all four products, ProductConfigurationTests, String Catalog compilation, localized dynamic UI/VoiceOver output, Soccer/Tower retry telemetry, and workflow execution; no GitHub Actions run was started
Product decisions made by user: none; the correction applies the reviewer findings without changing vocabulary or activity behavior
Remaining blockers: deliberate full manual macOS run, native-language review of fallback entries, device VoiceOver/layout/RTL QA, and the remaining Language/global release work
Master-plan sections updated: Current Active Phase, exact next implementation unit, localization status, and Sprint Log
Reviewer result: correction prepared for independent review; macOS confirmation pending

### 2026-09-03 — C1 Language Learn Letters release audit
Status: Windows-static implementation audit complete; release validation pending
Commit(s): C1 checkpoint containing this entry, `checkpoint: harden Language Learn Letters`
Files changed: Language-only Learn progression policy and final action; scene lifecycle speech stop; exact content/asset and progression tests; reviewed Android “Start over” localization; focused audit report; Living Status
Tests run: Android `LearnScreen.kt`, phone/tablet layouts, alphabet/example mappings, and `from_the_beginning` translations inspected read-only; localization/catalog, workflow, Math asset, asset-reference, and diff audits run on Windows; XCTest not executed because Swift/Xcode is unavailable on Windows
Tests authored: looping multi-card and one-card progression; Language factory policy across Plus English/Hebrew and English Only; all 53 Android example-word and illustration-ID mappings
Mac validation: required for all products, ProductConfigurationTests, String Catalog compilation, speech/replay timing and interruption, iPhone/iPad/Dynamic Type, VoiceOver, and mixed RTL/LTR interaction
Product decisions made by user: none; Android's looping/full-alphabet behavior and existing product-language policy remain authoritative
Remaining blockers: missing decorative letter-mascot art decision, deliberate full manual macOS run, native-language review, device accessibility/visual QA, and subsequent C2–C14 audits
Master-plan sections updated: Current Active Phase, exact next implementation unit, status board, release blockers, and Sprint Log; focused audit added
Reviewer result: C1 is Windows-statically audited, not release-complete

### 2026-09-03 — A2 final pre-Mac correction / Partial-success Simulator artifacts
Status: corrected and statically audited on Windows; first deliberate macOS validation pending
Commit(s): pre-Mac checkpoint containing this entry, `checkpoint: prepare first full Mac validation`
Files changed: preferred manual Simulator workflow, workflow contract audit, Windows operator guide, and current catalog-count/workflow status documentation
Tests run: localization direct-literal/dynamic-boundary/key/catalog audit; 463-key 11/10-locale catalog validation; all-workflow trigger and preferred workflow contract audit; Math asset audit; diff and complete staged-diff checks
Mac validation: not run; the user must deliberately start the first `run_tests=true`, `product=all` validation
Product decisions made by user: learned-language selection remains exclusively in Parent Area and is not duplicated on child-facing Home; C2 was explicitly deferred
Remaining blockers: first full manual macOS build/XCTest run and the existing device, visual, accessibility, linguistic, backend, commerce, privacy, and release gates
Master-plan sections updated: current localization count, current workflow behavior, and this Sprint Log; historical checkpoint counts preserved
Reviewer result: pre-Mac correction prepared for review; macOS confirmation pending

### 2026-09-03 — A2 Mac gate correction #2 / Shared compile diagnostics
Status: reviewer-diagnosed compiler error and Swift-concurrency warning corrected; clean macOS rerun pending
Commit(s): correction checkpoint containing this entry, `checkpoint: fix second Xcode compile gate`
Files changed: minimal `PingPongScene` initializer override; MainActor-isolated `AVSpeechSynthesizerDelegate` conformance; current Mac-gate and source-coupling status
Tests run: complete static review of both changed source files and adjacent initializers/delegate callbacks; localization, catalog, workflow, Math asset, diff, and complete staged-diff audits on Windows; Swift/XCTest not available on Windows
Mac validation: second deliberate gate used Xcode 26.6 / iPhoneSimulator 26.5; all four products reached Swift, String Catalog, asset-catalog, and universal arm64 + x86_64 Simulator compilation; the prior FoundationXML error was absent; 4/4 failed on the same no-argument `PingPongScene` override error and 4/4 emitted the same Tic-Tac-Toe delegate-isolation warning; no product packaged, tests did not run, and no smoke test passed
Product decisions made by user: none; no product behavior, routing, source membership, or C2 work changed
Remaining blockers: deliberate full rerun after this correction, then device/visual/accessibility/linguistic and existing release gates; target-wide source coupling remains a later build-architecture unit
Master-plan sections updated: Current Active Phase, exact next action, A2 status, release blockers, and Sprint Log
Reviewer result: correction prepared for review; clean macOS confirmation pending

### 2026-09-04 — C2 Language Letter Pairs release audit
Status: Windows-static implementation audit complete; macOS/device/shared final-feedback validation pending
Commit(s): C2 checkpoint containing this entry, `checkpoint: harden Language Letter Pairs`
Files changed: mixed any-two Pairs interaction and physical metadata; Letter Pairs session/provider/factory/continuous-round routing; learned-word speech/lifecycle; semantic retry telemetry; narrow Android points mapping; deterministic tests; focused audit; Living Status
Tests run: Android `LetterPairsFragment.kt`, phone/tablet/tile layouts, and known-fix policy inspected read-only; localization/catalog, Language content/assets, workflow, Math asset, source-structure, and diff audits run on Windows; XCTest not executed because Swift/Xcode is unavailable on Windows
Tests authored: four semantic groups/eight unique physical images; mixed arbitrary selection/deselection/correct/incorrect/completion; English/Hebrew speech and accessibility metadata; English Only policy; semantic ID versus physical ID; per-presentation first-attempt/retry semantics; no Math fields; Android `+1/-1` reward mapping and idempotent event identity
Mac validation: required for all four products, ProductConfigurationTests, Letter Pairs continuous rounds, points persistence, learned-language speech/cancellation, iPhone/iPad/Dynamic Type, VoiceOver, Reduce Motion, and mixed RTL/LTR interaction
Product decisions made by user: none; Android's current four-initial/eight-picture, any-two matching, learned-word speech, continuous-round, and points behavior remains authoritative
Remaining blockers: clean full manual Mac gate, final shared Minik/success/failure audio and art, native-language review, device accessibility/visual QA, and C3–C14
Master-plan sections updated: Current Status, completed/next Language C-unit, status board, release blockers, and Sprint Log; focused C2 audit added
Reviewer result: C2 Windows-static audit prepared for independent review; macOS compile/test and device confirmation pending

### 2026-09-04 — A2 Mac gate correction #3 / Five compiler errors and warning cleanup
Status: reviewer-diagnosed compiler errors and concrete Minik Swift warnings corrected; clean macOS rerun pending
Commit(s): correction checkpoint containing this entry, `checkpoint: fix third Xcode compile gate`
Files changed: escaping Parent Area ViewBuilder contract; Soccer prompt return; explicit optional Word Cards compact-map result; qualified Language initial-group helper; real M9 number-line representation case; nonisolated Tic-Tac-Toe speech-delegate callbacks with an explicit MainActor hop; two concrete warning cleanups; current Mac-gate status
Tests run: complete affected-source review; static C2 compile-hazard review; localization, catalog, workflow, Math asset, focused C2 content/structure, diff, and complete staged-diff audits on Windows; Swift/XCTest unavailable on Windows
Mac validation: third deliberate gate checked out `085d704f5e8451ac9bc4456b4b521e6a64227c3b`, used Xcode 26.6 / iPhoneSimulator 26.5, completed XcodeGen, attempted all four schemes, retained the FoundationXML and PingPongScene corrections, then failed all four builds on five distinct compiler errors; no product packaged, ProductConfigurationTests did not run, and no smoke test passed
Product decisions made by user: none; C2 behavior/tests remain unchanged and C3 was not started
Remaining blockers: deliberate clean all-product macOS rerun, ProductConfigurationTests, Simulator packaging/smoke validation, and existing device/visual/accessibility/linguistic/release gates
Master-plan sections updated: completion-estimate Mac-gate wording, Current Status, A2 status, release blocker, and Sprint Log; historical Gate-1/Gate-2/C2 facts preserved
Reviewer result: compile correction prepared for focused review; clean macOS confirmation pending

### 2026-09-04 — A2 Mac gate correction #4 / Two compiler errors
Status: reviewer-diagnosed compiler errors corrected without product behavior changes; clean macOS rerun pending
Commit(s): correction checkpoint containing this entry, `checkpoint: fix fourth Xcode compile gate`
Files changed: `LearningTextRepresentation` argument-label order in Language Word Cards; explicit `LazyVGrid` return in the C2 mixed board; current Mac-gate status
Tests run: complete static review of the two affected functions; localization, catalog, workflow, Math asset, diff, and complete staged-diff audits on Windows; Swift/XCTest unavailable on Windows
Mac validation: fourth deliberate gate checked out `898a8e652691451b63fedad952ce4f81bf16b2a8` and used Xcode 26.6; the previous five Gate-3 compiler errors and previous Tic-Tac-Toe concurrency warning did not recur; four `error:` occurrences represented exactly two unique source errors; all four requested builds failed, no product packaged, ProductConfigurationTests did not run, and a clean rerun remains pending
Product decisions made by user: none; Word Cards and C2 any-two Letter Pairs behavior remain unchanged, and C3 was not started
Remaining blockers: deliberate clean all-product macOS rerun, ProductConfigurationTests, Simulator packaging/smoke validation, and existing device/visual/accessibility/linguistic/release gates
Master-plan sections updated: current hardening summary, Current Status, Mac Gate #4 result, A2 status, release blocker, and Sprint Log; historical Gate-1 through Gate-3 facts preserved
Reviewer result: compile correction prepared for focused review; clean macOS confirmation pending

### 2026-09-04 — A2 Mac gate #5 / ProductConfigurationTests compatibility
Status: all four application targets compile and package successfully; stale test fixture corrected and statically audited on Windows; clean Mac XCTest execution pending
Commit(s): correction checkpoint containing this entry, `checkpoint: repair ProductConfigurationTests compatibility`
Files changed: semantically correct manifest `stableKey` in the Language word-level fixture; reusable ProductConfigurationTests compatibility audit; current Mac-gate status
Tests run: complete 78-file ProductConfigurationTests source/API sweep; manifest and LearningText call-order audit; constructor and qualified-member reconciliation; localization, catalog, workflow, Math asset, Language/C2 structure, compatibility, diff, and complete staged-diff audits on Windows; Swift/XCTest unavailable on Windows
Mac validation: Gate #5 checked out `7bc15113f3c2b77dfbe3856558e4caf5e647c538` with Xcode 26.6; all four application targets built, all four Simulator ZIPs packaged and uploaded, then ProductConfigurationTests compilation failed before execution on one missing `stableKey` argument and emitted one optional-`androidWordID` interpolation warning; no XCTest assertion executed
Product decisions made by user: none; production behavior is unchanged and C3 was not started
Remaining blockers: clean Mac ProductConfigurationTests compile/execution, Simulator smoke/device validation, and existing visual/accessibility/linguistic/release gates
Master-plan sections updated: current hardening summary, Current Status, Gate #5 result, A2 status, release blocker, and Sprint Log; all earlier Gate history preserved
Reviewer result: test-target compatibility correction prepared for focused review; Mac XCTest confirmation pending

### 2026-09-04 — A2 Mac gate #6 / First executed XCTest failures
Status: all test failures named by the Gate #6 brief are corrected as test-only defects; clean macOS XCTest confirmation pending
Commit(s): correction checkpoint containing this entry, `checkpoint: resolve first XCTest failures`
Files changed: Activity catalog casing expectation; unique progress-event fixture identity; deterministic Soccer/Tower whitespace and Word Build image-ready fixtures; stable non-optional word identity expectation from the existing Phase-41 hunk; typed M3 Build semantic assertion; tolerant Ping Pong center mapping assertion; current Mac-gate/runtime-QA status
Tests corrected: `testTicTacToeIsAJustForFunGameInBothLanguageProductsOnly`; `testLocalRepositoryPersistsAndRestoresVersionedSnapshot`; `testReducerAggregatesAttemptsOutcomesCompletionAndDuration`; `testBuiltDisplayTextRestoresWhitespaceWhenFollowingTokenIsAccepted`; `testWhitespaceIsNotDraggableAndProgressiveDisplayPreservesIt`; `testExpectedVisibleSequenceReconstructsExactLearnedWord`; `testCatalogMigratesLevelAFruitsInAndroidSourceOrder`; `testM3BuildKeepsTheMissingValueTaskInsideTheBuildInteraction`; `testDecorativeAreaIsNotPlayableTableInput`. The reviewer reports eight unique failing methods, while the supplied brief enumerates these nine names by listing both methods in the shared ActivityProgress failure class; no enumerated method was omitted.
Tests run: Windows test-compatibility, localization, catalog, Math-asset, workflow, focused Gate-6 source, diff, and complete staged-diff audits; XCTest was not rerun because Xcode is unavailable on Windows
Mac validation: Gate #6 checked out `b1c3e811da1dc72e3c0204c82e6c9596b8d85a9c` with Xcode 26.6; MinikPlus BUILD SUCCEEDED, ProductConfigurationTests compiled, its XCTest bundle loaded, 763 tests executed, and 18 failure/error occurrences were reported across exactly eight unique methods according to the reviewer; CI failed on assertions/semantic tests rather than compilation
Product decisions made by user: none; no production source or behavior changed, C3 stayed frozen, and the Ping Pong runtime serve-targeting concern remains open
Remaining blockers: clean Mac XCTest rerun; the seven separately recorded visual/runtime QA findings; existing device/accessibility/linguistic/release gates
Master-plan sections updated: engineering estimate, Current Status, Gate #6 result, runtime QA observations, A2 status, release blocker, and Sprint Log; all earlier gate history preserved
Reviewer result: repository evidence classifies the reported failures as stale/brittle fixtures or numeric assertion noise, plus one correct dirty hunk not present in the tested commit; macOS confirmation pending

### 2026-09-04 — Visual foundation and Language Home parity
Status: Windows-static implementation complete; independent visual review and macOS/device confirmation pending
Commit(s): visual-foundation checkpoint containing this entry
Files changed: separate shared Minik visual asset catalog sourced from existing Android product art; shared background/header/feedback/CTA primitives; illustration-led Language Home; Picture Memory Games grouping; Learn composition; deterministic grouping test; visual-asset audit; first-Simulator QA ledger
Tests run: Android screenshots, layouts, activity source, and drawable inventory inspected read-only; shared-asset, localization, catalog, workflow, Math-asset, test-compatibility, and diff audits run on Windows; XCTest and Simulator were not run because Xcode is unavailable on Windows
Tests authored: exact 13-item production grouping with Picture Memory under Games
Mac validation: required for asset-catalog compilation, iPhone/iPad/Dynamic Type/RTL/VoiceOver layouts, Reduce Motion feedback, and actual speech/audio
Product decisions made by user: Android Minik visual character is authoritative for Language; Picture Memory is a Game; learned-language selection remains Parent Area only
Remaining blockers: focused Soccer P0/visual correction, remaining activity presentation audits, Ping Pong coordinate/runtime correction, Parent Area parity, C3–C14 audits, Math consistency review, and all existing release gates
Reviewer result: source is prepared as the first focused visual checkpoint; no claim of runtime readiness

### 2026-09-04 — First-Simulator Soccer P0 and activity presentation
Status: Windows-static correction complete; independent visual review and macOS/device confirmation pending
Commit(s): focused Soccer/activity-presentation checkpoint containing this entry
Files changed: explicit ordered-token ball text rendering; original field/goal/goalkeeper/ball art; learned-word replay and background speech stop; ordered-token display contract/test; C2 tile framing and mascot; Picture Memory branded card backs/footer; first-Simulator ledger
Tests run: focused Soccer content/session and source contract audits plus the standard Windows audit suite; XCTest/Simulator not run on Windows
Tests authored: every English/Hebrew Soccer answer ball exposes a non-empty visible learning-text representation identical to its ordered token
Mac validation: required for ball legibility on iPhone/iPad, field cropping, goalkeeper/goal layering, VoiceOver, RTL, animation, and live speech
Product decisions made by user: none; the correction preserves semantic token identity, duplicate physical IDs, score matrix, retry/consumption rules, telemetry, and learned-language pronunciation
Remaining blockers: complete Language speech-path audit, remaining activity/Parent Area visuals, Ping Pong coordinate correction, C3–C14, Math consistency review, and existing release gates
Reviewer result: the reported P0 is fixed in source and explicitly test-covered; runtime confirmation remains required

### 2026-09-04 — First-Simulator Ping Pong input and composition
Status: Windows-static correction complete; independent visual review and macOS/device confirmation pending
Commit(s): focused Ping Pong checkpoint containing this entry
Files changed: tap-serve horizontal lane derivation; child-baseline serve-paddle animation; non-playable top-band Minik placement; rounded HUD typography; deterministic serve and coordinate assertions; first-Simulator ledger
Tests run: standard Windows audit suite and source compatibility audit; XCTest/Simulator not run on Windows
Tests authored: center aim, left/right preservation, tap-selected primary bounce depth, derived own/opponent bounce sides; existing decorative-area and invertible table-coordinate coverage retained
Mac validation: required for serve feel/trajectory, touch-to-table calibration, common iPhone/iPad composition, typography, and gameplay obstruction
Product decisions made by user: none; Tap still accepts the full legal table, child-half taps define the first bounce, Minik-half taps define the receiver bounce, and difficulty assistance/out behavior is preserved
Remaining blockers: complete Language speech-path audit, remaining activity/Parent Area visuals, C3–C14, Math consistency review, and existing release gates
Reviewer result: the concrete coordinate/model and obstruction findings are source-corrected and deterministic tests are authored; runtime confirmation remains required

### 2026-09-04 — Language speech-path static audit
Status: Windows-static correction complete; live Apple-platform audio confirmation pending
Commit(s): focused Language speech-path checkpoint containing this entry
Files changed: typed optional prompt/choice speech boundary; First Letter, picture/word, and Build Word provider cues; Multiple Choice and Build invocation/replay; Cards/Tower/Memory background cancellation; non-silent synthesizer fallback; speech ledger/audit/tests
Tests run: 26-contract Language speech source audit and the standard Windows audit suite; XCTest/Simulator/audio not run on Windows
Tests authored: English/Hebrew cue resolution for both First Letter directions, both picture/word directions, Build Word prompt/tokens, Hebrew speech override, and Math no-speech separation
Mac validation: required for actual audibility, installed voice selection/fallback, audio interruption, replay count, and background/foreground behavior
Product decisions made by user: none; activity correctness, progression, retry, telemetry, English/Hebrew policy, and Math behavior are unchanged
Remaining blockers: live audio retest, remaining activity/Parent Area visuals, C3–C14 release audits, Math consistency review, and existing release gates
Reviewer result: the previously unwired Multiple Choice and Build paths and silent missing-voice branch are corrected in source; Appetize versus product audio remains unproven

### 2026-09-04 — Parent Area visual parity
Status: Windows-static presentation correction complete; independent visual and Apple-device confirmation pending
Commit(s): focused Parent Area visual checkpoint containing this entry
Files changed: single white Minik modal composition; product close/logo art; compact grouped settings; yellow encouragement control; adaptive blue progress/records actions; visual contract and first-Simulator ledger
Tests run: Language visual, localization, catalog, product-policy source compatibility, Math asset, workflow-safety, and diff audits; XCTest/Simulator not run on Windows
Tests authored: strengthened Language visual source audit covers the Parent Area modal, close artwork, and action treatment; existing product policy tests remain authoritative
Mac validation: required for compact iPhone, iPad, Dynamic Type, VoiceOver, RTL, picker, toggle, progress, records, and dismissal behavior
Product decisions made by user: none; learned-language selection remains Parent-only, English Only remains fixed to English without Hebrew interface support, and Math retains Automatic/Manual controls
Remaining blockers: remaining activity visuals, C3–C14 release audits, Math consistency review, runtime speech/visual QA, and existing release gates
Reviewer result: the Parent Area source now follows the supplied Android modal composition without restoring a child-facing language selector or changing settings behavior

### 2026-09-04 — C3 First Letter picture-to-letter release audit
Status: Windows-static implementation audit complete; macOS/device confirmation pending
Commit(s): C3 checkpoint containing this entry, `checkpoint: harden First Letter picture to letter`
Files changed: explicit C3 multiple-choice presentation; learned-word prompt accessibility; stable semantic progress identity; production/development routing; deterministic provider/factory tests; focused release audit; visual contract and first-Simulator ledger
Tests run: Android `WriteScreen.kt`, localized instruction, distractor filtering, answer/retry lifecycle, and reference screenshot inspected read-only; Language visual/speech, localization, catalog, ProductConfigurationTests compatibility, workflow, Math asset, and diff audits run on Windows; XCTest/Simulator not run on Windows
Tests authored: English/Hebrew learned-word prompt speech; expected initial-concept progress identity distinct from presentation UUID; six-challenge retry-until-correct factory behavior
Mac validation: required for all four products, ProductConfigurationTests, image assets, speech/replay and interruption, 1.5-second retry timing, iPhone/iPad/Dynamic Type, VoiceOver learned-word announcement, Reduce Motion, and mixed RTL/LTR interaction
Product decisions made by user: none; Android's picture→initial semantics, distinct same-category distractors, learned-language speech, and retry behavior remain authoritative
Remaining blockers: clean Mac XCTest rerun, C3 runtime/device/linguistic validation, C4–C14 release audits, Math consistency review, and existing product release gates
Master-plan sections updated: Current Active Phase, completed/next Language unit, status board, release blockers, and Sprint Log; focused C3 audit added
Reviewer result: C3 is prepared for independent source review; no runtime readiness claim and no GitHub Actions run

### 2026-09-04 — C4 First Letter letter-to-picture release audit
Status: Windows-static implementation audit complete; macOS/device confirmation pending
Commit(s): C4 checkpoint containing this entry, `checkpoint: harden First Letter letter to picture`
Files changed: explicit C4 multiple-choice presentation; learned-word picture accessibility; stable semantic progress identity; production/development routing; deterministic provider/factory tests; focused release audit; visual contract and first-Simulator ledger
Tests run: Android `WriteScreen.kt`, reverse localized instruction, image/distractor filtering, answer/retry lifecycle, and reference screenshot inspected read-only; Language visual/speech, localization, catalog, ProductConfigurationTests compatibility, workflow, Math asset, and diff audits run on Windows; XCTest/Simulator not run on Windows
Tests authored: English/Hebrew learned-word speech on every image choice; expected initial-concept progress identity distinct from presentation UUID; six-challenge retry-until-correct factory behavior
Mac validation: required for all four products, ProductConfigurationTests, image assets/grid, speech/replay/selection and interruption, 1.5-second retry timing, iPhone/iPad/Dynamic Type, VoiceOver learned-word announcement, Reduce Motion, and mixed RTL/LTR interaction
Product decisions made by user: none; Android's initial→picture semantics, distinct same-category image distractors, learned-language speech, and retry behavior remain authoritative
Remaining blockers: clean Mac XCTest rerun, C4 runtime/device/linguistic validation, C5–C14 release audits, Math consistency review, and existing product release gates
Master-plan sections updated: Current Active Phase, completed/next Language unit, status board, release blockers, and Sprint Log; focused C4 audit added
Reviewer result: C4 is prepared for independent source review; no runtime readiness claim and no GitHub Actions run

### 2026-09-04 — C5 Picture-to-Word release audit
Status: Windows-static implementation audit complete; macOS/device confirmation pending
Commit(s): C5 checkpoint containing this entry, `checkpoint: harden Picture to Word`
Files changed: explicit C5 multiple-choice presentation; learned-word prompt accessibility; stable vocabulary progress identity; production/development routing; deterministic provider/factory tests; focused release audit; visual contract and first-Simulator ledger
Tests run: Android `WriteScreen.kt`, text-choice routing, answer/retry lifecycle, and Picture-to-Word reference screenshot inspected read-only; Language visual/speech, localization, catalog, ProductConfigurationTests compatibility, workflow, Math asset, and diff audits run on Windows; XCTest/Simulator not run on Windows
Tests authored: English/Hebrew pictured-word prompt speech and selectable-word cue availability; prompt/answer/progress vocabulary identity; presentation UUID separation; six-challenge retry-until-correct factory behavior
Mac validation: required for all four products, ProductConfigurationTests, vocabulary images, prompt/choice speech and interruption, 1.5-second retry timing, compact/long word layout, iPhone/iPad/Dynamic Type, VoiceOver, Reduce Motion, and mixed RTL/LTR interaction
Product decisions made by user: none; Android's picture→word semantics, same-category distractors, learned-language speech, and retry behavior remain authoritative
Remaining blockers: clean Mac XCTest rerun, C5 runtime/device/linguistic validation, C6–C14 release audits, Math consistency review, and existing product release gates
Master-plan sections updated: Current Active Phase, completed/next Language unit, status board, release blockers, and Sprint Log; focused C5 audit added
Reviewer result: C5 is prepared for independent source review; no runtime readiness claim and no GitHub Actions run

### 2026-09-04 — C6 Word-to-Picture release audit
Status: Windows-static implementation audit complete; macOS/device confirmation pending
Commit(s): C6 checkpoint containing this entry, `checkpoint: harden Word to Picture`
Files changed: explicit C6 multiple-choice presentation; learned-word picture accessibility; stable vocabulary progress identity; production/development routing; deterministic provider/factory tests; focused release audit; visual contract and first-Simulator ledger
Tests run: Android `WriteScreen.kt`, image-choice routing, answer/retry lifecycle, and Word-to-Picture reference screenshot inspected read-only; Language visual/speech, localization, catalog, ProductConfigurationTests compatibility, workflow, Math asset, and diff audits run on Windows; XCTest/Simulator not run on Windows
Tests authored: English/Hebrew prompt text/speech and pictured-word cue availability; prompt/answer/progress vocabulary identity; presentation UUID separation; six-challenge retry-until-correct factory behavior
Mac validation: required for all four products, ProductConfigurationTests, vocabulary image grid, prompt/selection speech and interruption, 1.5-second retry timing, iPhone/iPad/Dynamic Type, VoiceOver, Reduce Motion, and mixed RTL/LTR interaction
Product decisions made by user: none; Android's word→picture semantics, same-category image distractors, learned-language speech, and retry behavior remain authoritative
Remaining blockers: clean Mac XCTest rerun, C6 runtime/device/linguistic validation, C7–C14 release audits, Math consistency review, and existing product release gates
Master-plan sections updated: Current Active Phase, completed/next Language unit, status board, release blockers, and Sprint Log; focused C6 audit added
Reviewer result: C6 is prepared for independent source review; no runtime readiness claim and no GitHub Actions run

### 2026-09-04 — C7 Build Word release audit
Status: Windows-static implementation audit complete; macOS/device confirmation pending
Commit(s): C7 checkpoint containing this entry, `checkpoint: harden Build Word`
Files changed: typed Word Build content/validation; whitespace-free physical tokens and progressive exact display; explicit word presentation/accessibility; final-word speech; immediate-prefix semantic telemetry; tracker support/tests; provider/session/factory tests; focused release audit and first-Simulator ledger
Tests run: Android build route and reference screenshot inspected read-only; Language visual/speech, localization, catalog, ProductConfigurationTests compatibility, workflow, Math asset, and diff audits run on Windows; XCTest/Simulator not run on Windows
Tests authored: generated word/target identity; whitespace token exclusion; deterministic multiword progressive display; six immediate-prefix challenges; semantic word+token retry telemetry with skill/no-Math assertions
Mac validation: required for all four products, ProductConfigurationTests, tap/drag and duplicate-letter behavior, multiword whitespace, final auto-advance, speech sequence/interruption, iPhone/iPad/Dynamic Type, VoiceOver/keyboard/Switch Control, Reduce Motion, and mixed RTL/LTR interaction
Product decisions made by user: none; Android's ordered construction, immediate correctness, duplicate-letter, speech, and retry semantics remain authoritative
Remaining blockers: clean Mac XCTest rerun, C7 runtime/device/linguistic validation, C8–C14 release audits, Math consistency review, and existing product release gates
Master-plan sections updated: Current Active Phase, completed/next Language unit, status board, release blockers, and Sprint Log; focused C7 audit added
Reviewer result: C7 is prepared for independent source review; no runtime readiness claim and no GitHub Actions run

### 2026-09-05 — Independent visual review corrections before C8
Status: Windows-static correction complete; independent Apple-platform visual confirmation pending
Commit(s): focused correction checkpoint containing this entry, `checkpoint: fix independent visual review findings`
Files changed: Android-exact 13-activity artwork mapping and provenance manifest/audit; four missing directional/language asset variants; Android top Home hierarchy; dedicated Language Learn composition; Language Soccer first-three-launch introduction and colored ordered-token controls; blank Android-gradient Memory backs; Parent Area sheet presentation; readiness ledgers and deterministic tests
Tests run: Android production layouts/assets and supplied screenshots inspected read-only; visual asset inventory/provenance, Language visual/speech, localization/catalog, ProductConfigurationTests compatibility, workflow, Math asset, and diff audits run on Windows; XCTest/Simulator not run on Windows
Tests authored: exact English/Hebrew 13-activity artwork mapping including intentional First Letter sharing and distinct Picture-to-Word/Word-to-Picture art; Soccer introduction first-three-presentation persistence
Mac validation: required for Home hierarchy, Parent sheet detents/dimming, dedicated Learn sizing, Soccer introduction/audio/control composition, blank Memory backs, all four products, and ProductConfigurationTests
Product decisions made by user: Parent Area remains the only learned-language selector; Home uses the yellow Home control and trophy Records control; Math Learn and Math Soccer ball controls remain unchanged
Remaining blockers: clean Mac XCTest rerun; runtime speech/performance/Ping Pong touch confirmation; independent review of these partial visual corrections; C8–C14 release audits; Math consistency review; and existing release gates
Reviewer result: prior `UNRESOLVED: 0` language was corrected; Home, Learn, Soccer, Memory, and Parent remain partial until runtime visual confirmation, and C9/C11/C13 remain explicitly open

### 2026-09-05 — C8 Language Mixed release audit
Status: Windows-static implementation audit complete; macOS/device confirmation pending
Commit(s): C8 checkpoint containing this entry, `checkpoint: harden Language Mixed`
Files changed: typed child presentation routing for both choice directions and Word Build; atomic/no-duplicate transition, semantic choice identity/speech, and Mixed per-token telemetry tests; focused C8 audit and release evidence
Tests run: Android Mixed launch/transition source inspected read-only; focused C8, Language visual/speech, localization/catalog, ProductConfigurationTests compatibility, workflow, Math asset, and diff audits run on Windows; XCTest/Simulator not run on Windows
Tests authored: failed threshold transition rollback; English/Hebrew semantic identity and speech for both choice modes; per-token Mixed Word Build family/skill/retry/no-Math assertions
Mac validation: required for all four products, ProductConfigurationTests, 20/10/5 presentation transitions/repeat, retry and telemetry exactness, learned-language speech/replay/interruption, iPhone/iPad/Dynamic Type, VoiceOver/keyboard/Switch Control, Reduce Motion, and mixed RTL/LTR interaction
Product decisions made by user: none; the previously approved capability-enabled 20/10/5 Android schedule remains authoritative
Remaining blockers: clean Mac XCTest rerun, C8 runtime/device/linguistic/visual validation, C9–C14 release audits, Math consistency review, and existing product release gates
Master-plan sections updated: Current Active Phase, completed/next Language unit, status board, release blockers, and Sprint Log; focused C8 audit added
Reviewer result: C8 is prepared for independent source review; no runtime readiness claim and no GitHub Actions run

### 2026-09-05 — C9 Language Word Cards release audit
Status: Windows-static implementation audit complete; macOS/device confirmation pending
Commit(s): C9 checkpoint containing this entry, `checkpoint: harden Language Word Cards`
Files changed: dedicated Android-faithful Cards composition using the original background/logo/close/speaker/mascot art; source-matched card and word gradients; whole-screen manual advance; focused C9 audit and release evidence
Tests run: Android RandomWordCards source/layout and supplied screenshot inspected read-only; focused C9, visual provenance, Language visual/speech, localization/catalog, ProductConfigurationTests compatibility, workflow, Math asset, and diff audits run on Windows; XCTest/Simulator not run on Windows
Tests authored: none; existing deterministic CardsSession and LanguageWordCardsContentProvider coverage was reviewed and retained
Mac validation: required for all four products, ProductConfigurationTests, background crop/composition, manual-versus-timeout cancellation, continuous bags, long/multiword fit, learned-language speech/replay/interruption, iPhone/iPad/Dynamic Type, VoiceOver/keyboard/Switch Control, Reduce Motion, and mixed RTL/LTR interaction
Product decisions made by user: none; Android learned-text-only Cards behavior and existing product/language policy remain authoritative
Remaining blockers: clean Mac XCTest rerun, C9 runtime/device/linguistic/visual validation, C10–C14 release audits, Math consistency review, and existing product release gates
Master-plan sections updated: Current Active Phase, completed/next Language unit, status board, release blockers, and Sprint Log; focused C9 audit added
Reviewer result: C9 is prepared for independent source review; no runtime readiness claim and no GitHub Actions run

### 2026-09-05 — Post-C9 independent-review corrections

Commit(s): correction checkpoint containing this entry, `checkpoint: fix post-C9 independent review findings`
Files changed: Android-sourced interface translations and reproducible migration/provenance; a distinct truthful Home trophy leaderboard boundary; stable `StudyCardID` timer guards and deterministic Cards race coverage; focused audit contracts
Tests run: focused Cards, Language visual, localization/catalog, visual provenance, ProductConfigurationTests compatibility, workflow, Math asset, and diff audits on Windows; XCTest/Simulator not run
Tests authored: stale timer after manual advance is a no-op without skipping; one presentation advances at most once; current timed presentation advances normally
Mac validation: pending for compilation, XCTest, Simulator presentation, VoiceOver, speech, and lifecycle behavior
Product decisions made by user: none; Android Home trophy leaderboard semantics and approved C9 product behavior were preserved
Remaining blockers: clean Mac XCTest rerun, runtime/device/linguistic/visual validation, C10-C14 release audits, Math consistency review, and existing release gates
Reviewer result: corrections prepared for independent source review; no CI run and no runtime readiness claim

### 2026-09-05 — C10 Language Soccer final release audit

Commit(s): C10 checkpoint containing this entry, `checkpoint: harden Language Soccer final audit`
Files changed: focused C10 static audit; source/Android behavior evidence; current phase, roadmap board, blockers, and Sprint Log
Tests run: Android Soccer source/layout/string and supplied references inspected read-only; focused C10 plus full Windows-static localization/catalog, visual provenance, Language visual/speech/Cards, ProductConfigurationTests compatibility, workflow, Math asset, and diff audits; XCTest/Simulator not run
Tests authored: no new XCTest cases; the focused audit locks existing deterministic score, token, continuous-pool, telemetry, speech, lifecycle, direction, accessibility, and Reduce Motion coverage
Mac validation: compilation, XCTest, Simulator/device, VoiceOver, speech/audio, lifecycle, RTL/LTR, and visual validation pending
Product decisions made by user: none; Android Language Soccer semantics remain authoritative and Math Soccer controls were not changed
Remaining blockers: clean Mac gate, C10 runtime/independent review, C11-C14, Math consistency review, and existing release gates
Reviewer result: C10 prepared for independent source review; no CI run and no runtime readiness claim

### 2026-09-05 — C11 Language Tower / Alphabet Blocks final release audit

Commit(s): C11 checkpoint containing this entry, `checkpoint: harden Language Tower final audit`
Files changed: original Tower mascot and branded replay composition; focused C11 audit/evidence; current phase and Sprint Log
Tests run: Android source and supplied reference inspected read-only; focused C11 and Windows-static regression audits; XCTest/Simulator not run
Tests authored: no new XCTest cases; focused audit locks existing deterministic session/provider/telemetry coverage
Mac validation: compilation, XCTest, device drag/accessibility, layout, speech, lifecycle, RTL/LTR, and visual validation pending
Remaining blockers: clean Mac gate, C11 runtime/independent review, C12-C14, Math consistency review, and existing release gates
Reviewer result: C11 prepared for independent source review; no CI run and no runtime readiness claim

### 2026-09-05 — C12 Language Picture Memory final release audit

Commit(s): C12 checkpoint containing this entry, `checkpoint: harden Language Picture Memory final audit`
Files changed: focused C12 static audit/evidence; current phase, roadmap board, blockers, and Sprint Log
Tests run: Android source/layout/string and supplied reference inspected read-only; focused C12 plus Windows-static regression audits; XCTest/Simulator not run
Tests authored: no new XCTest cases; focused audit locks existing deterministic provider/session/catalog coverage
Mac validation: compilation, XCTest, iPhone/iPad layout, Dynamic Type, VoiceOver/Switch Control, speech, lifecycle, RTL/LTR, feedback, and visual validation pending
Product decisions made by user: none; the approved Games grouping and blank Android-gradient backs were preserved
Remaining blockers: clean Mac gate, C12 runtime/independent review, C13-C14, Math consistency review, and existing release gates
Reviewer result: C12 prepared for independent source review; no CI run and no runtime readiness claim

### 2026-09-05 — C13 Language Tic-Tac-Toe final release audit

Commit(s): C13 checkpoint containing this entry, `checkpoint: harden Language Tic-Tac-Toe final audit`
Files changed: exact Android Tic-Tac-Toe gameplay mascot/provenance; restored branded composition and score treatment; focused C13 audit/evidence; current phase and Sprint Log
Tests run: Android source/layout/resources and supplied reference inspected read-only; focused C13 plus Windows-static regression audits; XCTest/Simulator not run
Tests authored: no new XCTest cases; focused audit locks existing deterministic session/AI/preferences/catalog coverage and the ungraded production route
Mac validation: compilation, XCTest, iPhone/iPad layout, Dynamic Type, VoiceOver/Switch Control, speech/audio/timing, lifecycle, RTL, Reduce Motion, and visual validation pending
Product decisions made by user: none; Android just-for-fun semantics and Random/Adaptive compatibility remain preserved
Remaining blockers: clean Mac gate, C13 runtime/independent review, C14 parity lock, Math consistency review, and existing release gates
Reviewer result: C13 prepared for independent source review; no CI run and no runtime readiness claim

### 2026-09-05 — C14 Language production parity lock

Commit(s): C14 checkpoint containing this entry, `checkpoint: lock Language production parity`
Files changed: 13-row production parity record; focused C14 audit/evidence; dormant child-Home language-selector helper removal; explicit Learn/Cards/Tic-Tac-Toe non-mastery test; current phase and Sprint Log
Tests run: focused C14 record/source/provenance audit plus full Windows-static regression audits; XCTest/Simulator not run
Tests authored: one deterministic XCTest locks Learn, Word Cards, and Tic-Tac-Toe outside mastery; focused PowerShell audit locks all reviewer-specified C14 fail conditions
Mac validation: compilation, XCTest, Simulator/device, VoiceOver/Switch Control, speech/audio, Dynamic Type, lifecycle, RTL/LTR, and independent visual/linguistic validation remain pending per record
Product decisions made by user: no new decisions; Parent-only learned-language selection, Picture Memory Games grouping, ungraded Cards/Tic-Tac-Toe, and specialized Soccer/Tower telemetry were preserved
Remaining blockers: clean Mac gate, C1-C14 runtime/independent review gates, Math consistency review, and existing release gates
Reviewer result: C14 prepared for independent aggregate source review; no CI run and no runtime readiness claim

### 2026-09-05 — Post-C14 independent-review corrections

Commit(s): correction checkpoint containing this entry, `checkpoint: fix post-C14 independent review findings`
Files changed: hidden-score Tic-Tac-Toe presentation correction and guard; Android-exact Tower lower-composition assets/provenance and Language-only layout; tap-only Soccer introduction localization migration/audit; focused C10/C11/C13 evidence; current status
Tests run: focused Soccer interaction/localization, Tower composition, Tic-Tac-Toe, visual asset/provenance, localization/catalog, Language visual/speech/Cards/C14, ProductConfigurationTests compatibility, workflow-safety, Math asset, and diff audits on Windows; XCTest/Simulator not run
Tests authored: static C13 source guard rejects direct score rendering; C11 composition audit requires exact lower assets, locked base, bottom-up growth, multi-color blocks, and Math-path isolation; C10 audit verifies native button activation, visible/spoken copy identity, and tap-only text in all 11/10 locale policies
Mac validation: compilation, XCTest, Simulator/device visuals, VoiceOver/Switch Control, speech/audio, lifecycle, RTL/LTR, and independent linguistic review remain pending
Product decisions made by user: none; the correction restores the reviewed hidden-score policy, completes the Android-referenced Tower composition, and documents the existing native iOS tap-to-kick adaptation without changing activity semantics
Remaining blockers: clean Mac gate; runtime/linguistic/visual confirmation for the corrected surfaces; English Only D1/D2; Math visual consistency; and existing release gates
Reviewer result: independent findings corrected in source/static contracts; no CI run and no runtime readiness claim

### 2026-09-05 — D1 Minik Plus English production-policy hardening

Commit(s): policy checkpoint containing this entry, `checkpoint: harden Minik Plus English production policy`
Files changed: deterministic English Only production-policy XCTest coverage; source/static policy audit; policy evidence; current status
Tests run: English Only production-policy audit and applicable Windows-static regression checks; XCTest/Simulator not run
Tests authored: exact 13-route/product-isolation, non-Hebrew English artwork, English learned-text/speech metadata, fixed configuration, restored-state, interface-locale, and Parent-policy guards
Mac validation: compilation, XCTest, all 13 route launches, speech, Parent behavior, Arabic RTL/English LTR, accessibility, performance, and independent visual/linguistic review remain pending
Product decisions made by user: none; learned English remains fixed and selection remains Parent-read-only
Remaining blockers: D2 catalog/visual lock, Math visual consistency, clean Mac gate, runtime confirmation, and existing release gates
Reviewer result: D1 prepared for independent source review; no CI run and no runtime readiness claim

### 2026-09-05 — D2 English Only localization / visual lock

Commit(s): parity checkpoint containing this entry, `checkpoint: lock English Only product parity`
Files changed: deterministic 469-or-later key/10-locale catalog parity and surface audit; visual/direction evidence; current status
Tests run: catalog validator, English Only parity/policy audits, localization audit, and applicable Windows-static Language regression checks; XCTest/Simulator not run
Tests authored: catalog key equality/minimum count, exact locale set, Hebrew-state exclusion, Arabic-interface/English-learned direction boundary, and Home/Parent/Cards/Soccer/Tower/Memory/Tic-Tac-Toe static visual guards
Mac validation: compilation, XCTest, all 13 routes, Arabic RTL with English LTR, speech, accessibility, performance, and independent visual/linguistic review remain pending
Product decisions made by user: none; learned content remains English rather than following interface translation
Remaining blockers: Math visual consistency, clean Mac gate, runtime confirmation, and existing release gates
Reviewer result: D2 prepared for independent source review; no CI run and no runtime readiness claim

### 2026-09-05 — Minik Math visual consistency

Commit(s): visual checkpoint containing this entry, `checkpoint: harden Math visual consistency`
Files changed: branded replay controls on specialized Math surfaces; 13-row M1/M5/M10 visual record; deterministic Math visual audit; evidence; current status
Tests run: Math visual/static audit, Math asset validation, ProductConfigurationTests compatibility, localization/catalog, workflow-safety, and applicable shared visual regressions on Windows; XCTest/Simulator not run
Tests authored: exact 13-row record, M1/M5/M10 representative coverage, all M1-M10 factory identity coverage, shared frame/surface/close/feedback, branded replay, LTR mathematics, Level 1-10, no learned-language state, and no development-route guards
Mac validation: compilation, XCTest, iPhone/iPad visuals, Dynamic Type, VoiceOver/Switch Control, RTL interface, speech, interactions, Ping Pong serve feel, performance, and independent visual review remain pending
Product decisions made by user: none; no Android Math authority was invented and no educational/reward behavior changed
Remaining blockers: shared second-Simulator readiness review, clean Mac gate, runtime confirmation, and existing release gates
Reviewer result: Math visual consistency prepared for independent source review; no CI run and no runtime readiness claim

---

### 2026-09-05 — Shared practice visual Mac-gate repair

Status: source repair and Windows compile-risk audit complete; Xcode confirmation pending
Commit(s): local checkpoint containing this entry, `checkpoint: repair shared practice visual compile defect`
Files changed: two choice-style identifier references; focused source-contract audit and Language visual-audit integration; detailed 56-file compile-risk evidence; current gate status
Root cause: `a90e0a0` added idle border conditions using helper-local `state` outside its scope; the component has always stored `feedbackState`
Tests run: all 20 applicable Windows/static scripts, seven focused in-memory regression mutations, and diff checks; no Swift parser/compiler, Xcode, XCTest, or Simulator execution available in this session
Mac validation: required for all four schemes and ProductConfigurationTests; the supplied failed run checked out exactly `d6b3cbfad3a0cd5f9fe872a5965beac77ac7d846`
Product decisions made by user: none; idle gradient, feedback colors/widths, accessibility, and product routes preserved
Remaining blockers: clean Mac compile/test rerun and existing release gates; no additional concrete compile defect found in `b1c3e81..d6b3cbf`
Preserved work: Phase 41 dirty paths excluded from staging; one local checkpoint only; review exports outside the repository; no push or CI
Reviewer result: source audit complete with explicit Windows limitations; independent and Apple-platform confirmation pending

---

### 2026-09-05 - Cards accessibility second Mac failure / red-team correction

Sprint name: Root-cause the shared Cards API failure and correct the previous review process
Commit(s): local checkpoint containing this entry, `checkpoint: repair Cards SwiftUI accessibility compile defect`
Files changed: one Cards accessibility expression; focused six-mutation API guard and Word Cards integration; corrected prior analysis; new evidence-separated audit; living plan status
Behavior changed: the existing tap surface explicitly supplies the default accessibility action and calls the same manual advance operation; timing, speech, lifecycle, visuals and activity mechanics remain intact
Validation performed: all 21 applicable Windows audits passed; entire 133-file Sources scan and repeated 56-file committed Swift review; selective staged diff and preservation checks recorded in the external export
Mac validation: pending for all four schemes and ProductConfigurationTests; supplied failed run was exactly `d2d8d79deeb51cb65dc92a8a1d82187849e9cc75`
Review correction: previous Cards overload-resolution wording exceeded its evidence and missed this invalid call; authoritative API shapes and real-compiler uncertainty are now reported separately
Remaining blockers: exact SDK actor/generic/overload confirmation, possible later compiler errors, clean Mac test rerun and existing release gates; no additional concrete defect identified by this review
Preservation: all pre-existing Phase 41 work excluded; no AGENTS.md staging, push, CI/workflow execution, or workflow-trigger changes

---

### 2026-09-05 — M3 Build XCTest root-cause correction

Status: TEST_DEFECT classified before repair; source repair and deterministic regression coverage complete; Mac XCTest confirmation pending
Commit(s): single local checkpoint containing this entry, `checkpoint: correct M3 Build XCTest factory boundary`; investigation parent `180155bedc7d421e3c5ffc391e943a32bffec604`
Files changed: older-factory Build test, two dedicated M3 test files, focused boundary guard and standard-test-audit integration, root-cause document, living plan
Root cause: Gate #6 asserted `.math(.missingValueExpression)` on the generic `MathContentProvider` path, which always emits `.mathExpression`; the canonical dedicated M3 production path already supplies typed prompts
Deterministic coverage: fixed oracle for all six production challenges; all 16 M3 forms and three missing positions; exact generic missing-addend prompt plus full-sequence submission; Windows guard demonstrated rejection before repair and five mutation checks
Validation: all 22 applicable Windows/static audits and a finite-domain source projection; exact results and Phase 41 preservation proof are recorded in the external root-cause export
Mac evidence supplied: Xcode 26.6 / Swift 6.3.3 built all four apps and executed 797 tests, 796 passed; the repaired tests have not run on this Windows host
Product decisions made by user: none; no production or canonical Math changes
Review correction: prior Gate #6 M3 resolution claim was unsupported; no other Gate #6 correction was found to use the same wrong-factory reasoning
Preservation: all 805 pre-existing paths and 408 short-status rows retained; only the seven task files eligible for the local checkpoint; no Phase 41 or AGENTS.md staging
Remaining blockers: future authorized Mac confirmation and existing release gates; no push, fetch, CI, workflow execution or trigger changes

---

### 2026-09-06 — Language reconstruction unit 1: shell and interface locale

Starting HEAD: 084ca2a3405700fa65841beadd3685ddcaec5d6c. Selective local checkpoint; no push or CI.
Android MainActivity → IntroFragment (IntroScreen.kt) → ButtonsMenuFragment, phone/tablet shell layouts, Parent source/dialog, full wordmark and original opening clip were inspected. The production shell now restores Intro, menu and activity return paths, a compact Parent dialog and canonical activity cards. Existing local settings/progress/rewards are reused.
The Hebrew failure includes English catalog values and eager process-language String lookup. 78 Android-mapped keys, deferred title/name keys, explicit LocalizedStringResource locale lookup, and regression tests/audits address these boundaries. Apple's documentation confirms that the other String initializer's locale argument only formats interpolations.
Windows catalog/policy/test-source/asset/provenance checks and seven negative regression fixtures passed; new XCTest and runtime rendering remain pending. All remaining activities are OPEN in the ledger. The 805-path pre-existing-work snapshot reports zero changes.

---

### 2026-09-06 - Language reconstruction: Learn, Pairs, choices, Build and Cards

Learn checkpoint 4144910 restores 53 typed cards / 106 original letter forms and the divider. The next source unit rebuilds fixed Pairs/choice/Build compositions, original reaction/star/audio/font assets, typed host Build clues, and actual speech-completion progression. Choice and completed-word rewards preserve Android's distinct local bonus and displayed streak; stale event replay and re-entry are covered. Cards now uses the original full wordmark, inset Play/X, shorter short-word card, larger raised mascot and active-scene presentation timers; the prior explicit default accessibility action is retained.
Validation: focused Pairs/choice/Build negative guards and local test-source/localization/speech/production checks pass; Cards/API/visual guards also pass after following the new shared header; all six historical API-negative fixtures remain rejected. New XCTest is unexecuted on Windows. All 805 pre-existing paths remain unchanged. Full sixteen-reference crosswalk records outstanding source gaps explicitly. No push or CI; complete Language source gate still OPEN.

Bounded recovery review: Android Write exposes Next immediately after a wrong choice while retaining the same challenge for retry, so the iOS choice page now follows `canAdvanceManually` without hiding Next during its transient incorrect state. Rejected Build-letter event IDs are persisted as zero-point, streak-neutral ledger markers, preventing an old event from resetting a newer bonus run after service recreation. Continuous Build uses an independent monotonically increasing presentation identity so a repeated word/token in a later generated batch begins again at attempt 1. The owner contract preserves Learn replay/speech with an attractive triangular Play-style control rather than speaker/Listen treatment. Android Cards source, layouts, and canonical screenshot confirm the visible localized “Cards” heading, which remains.

### 2026-09-06 — Language Picture Memory reconstruction

Picture Memory bounded reconstruction: Android `MemoryGameFragment.kt`, both `fragment_memory_game.xml` layouts, its card/background resources, vocabulary loader/models, strings, dimensions, and reference 10 establish a six-pair fixed 3x4 image-to-identical-image board. The Language-only iOS route now uses the exact decoded Android pastel scene, the original mascot and three blank-back palettes; ordinary phones show all 12 square cards without a board ScrollView, while small/accessibility layouts use the shared deliberate fallback and iPad follows sw600dp scale. Accepted reveals retain exact-once learned speech and existing attempts. The second card starts an identity-guarded one-second evaluation; mismatches close after flip safety, matches remain, stale/lifecycle callbacks cannot touch a later presentation, and completion starts a clean provider-backed round. No generic fraction, manual Continue, mastery/reward UI, or Math presentation change was introduced. Focused Windows audits pass and deterministic XCTest was authored but not run; Xcode, Simulator/device visuals, VoiceOver, Reduce Motion and real audio remain pending. The only remaining reconstruction units are Soccer, Tower, Tic-Tac-Toe, Parent Levels, and the final Mixed/system pass.

### 2026-09-06 — Language Tower / Alphabet Blocks reconstruction

Tower bounded reconstruction: full Android `LettersTowerFragment.kt`, phone/sw600 layouts, reference 11, strings, dimensions, animations, sound/speech paths and all live asset alternatives establish a learned-word target with speaker replay, stable physical letter blocks, an automatically locked first block, correct-next-only bottom-up placement, automatic whitespace spacers, non-consuming wrong choices, final letter then word speech, confetti, fixed +2 completion and continuous words. The Language-only iOS route now reproduces the canonical exact pastel scene, sitting gift mascot, `sand2` and `send_pile`, with loose blocks kept outside a generic grid and the full usable play scene visible together. Typed attempts retain semantic item identity while presentation UUIDs guard exact-once completion and stale delayed transitions. Math Tower remains on its prior value-ordering path. Focused Windows audits pass and deterministic XCTest was authored but not run; Xcode, Simulator/device visuals, VoiceOver, Reduce Motion and real audio remain pending. The remaining OPEN reconstruction units are Soccer, Parent Levels, and the final Mixed/system review.

### 2026-09-06 — Language Tic-Tac-Toe bounded reconstruction

Tic-Tac-Toe bounded reconstruction: the complete live Android `TicTacToeFragment.kt`, four phone/sw600dp regular/Plus layouts, reference 12, game/AI/reset paths, strings, dimensions/colors, assets, speech/sounds, animation timing and lifecycle cleanup establish the child-first continuous just-for-fun game. The dedicated iOS screen now uses the exact decoded pastel scene and actual board-holding Plus mascot instead of the dab substitute, with an inside close, gradient title, X/O choice, status and complete purple/pink/teal-edged white board together without normal-phone scrolling. The existing default-X and retained/unlocked mark selection, A-E/Random/Adaptive mapping, random/established Medium/minimax AI, atomic single AI response, hidden cumulative scores, result timing, speech/audio and cancellation remain unchanged. Focused Windows audits pass and one deterministic stale-new-round XCTest was authored but not run; Xcode, Simulator/device visuals, VoiceOver/Switch Control, Reduce Motion and real audio remain pending. The remaining OPEN reconstruction units are Soccer, Parent Levels, and the final Mixed/system review.

### 2026-09-06 — Language Parent Levels reconstruction

The live Android path `IntroScreen` → `LanguagesAndLevelsDialogFragment` → `LevelsDifficultyDialogFragment` and its shared phone/tablet `dialog_levels_difficulty.xml` establish a compact modal with immediately persisted controls: Auto/manual Words A-E (default Auto at A), Soccer A-C (default A), and Tic-Tac-Toe A-E/Random/Adaptive (default Adaptive). The general word level is per local product/profile rather than per learned language; Manual filters the vocabulary curriculum stage used by production word sessions and does not change the learned language, interface locale, or Math level. The iOS Parent Levels action opens that destination, persists through the Parent settings repository boundary, and exposes it in Plus and fixed-English English Only. Soccer A/B/C and Tic-Tac-Toe have production effects. The follow-up Language Auto unit adds durable per-word/activity/stage evidence, exact Write/Tower/Soccer full-pool thresholds, the persisted two-pass gate, upward-only promotion, and previous/current vocabulary list-count ramp. Auto and Manual share the persisted A-E value exactly as Android does. Xcode/XCTest, phone/iPad rendering, Arabic RTL, VoiceOver and app-restart/background ramp verification remain pending. Status: `ANDROID_PARITY_IMPLEMENTED_SOURCE`; the final Mixed/system review remains OPEN.

### 2026-09-07 — Language Soccer bounded reconstruction

Starting HEAD: `2783566bc4503fa4340dd31905594b513ec47e98`. The complete live Android Soccer game/intro sources, phone/sw600 layouts, strings, dimensions, active assets, and binding references 08/09 were inspected read-only. The Language route now owns a fixed no-scroll field composition and upward drag release. The football follows the measured drag vector at Android's fixed speed/minimum upward component; keeper, posts, crossbar and goal use the same coordinate model; collision rebounds before a shot-ID-gated exact-once finalization. Cancelling below the release threshold produces no attempt or score. Existing ordered-token educational correctness, score matrix, retry/consumption, duplicates, learned speech/replay, continuous words, specialized telemetry and no-Math-field policy remain authoritative.

Persisted Parent Soccer A/B/C now controls Android-derived keeper reference sizes, first stationary/moving attempts, goal-mouth movement range, 3.0/1.1/0.8-second one-way sweep timing and the Android post-ten-shot goal-ratio adjustment/floors. A typed local full-pool exhaustion boundary is exposed for future Auto work without changing the global word-level engine. The first-three-presentation introduction and all 11 Full/10 English Only entries now describe drag; non-English updates remain `needs_review`. Math Soccer and every other activity are unchanged.

Deterministic XCTest source covers release/deadband cancellation, vector goal/miss, keeper/post/crossbar collision/rebound, velocity normalization, lifecycle exclusivity/stale/duplicate callbacks, all A/B/C first-keeper rules, sizes/speeds/adaptive floors/range, unresolved cancellation, and typed pool exhaustion; existing tests retain the complete score/consumption/retry/duplicate/speech/product-policy contracts. Focused and standard Windows audits are recorded in the checkpoint report; XCTest/Xcode/Simulator/device/audio/VoiceOver/RTL/visual and native-language validation remain pending. Global Language Auto is implemented at Windows-static source level; the final Mixed/system audit remains OPEN. No push or CI.

### 2026-09-07 — Android-derived Language Auto A-E progression

Starting HEAD: `3396f12f761b9dd15d9ee831463f5788533021d0`. The complete Android owning path was re-read through Intro/Parent mode storage, per-word counters, level gate, all three eligible activity pool boundaries, promotion/ramp mixing, and `MainActivity.onStop`. iOS Build Word is Android `WriteScreen`'s `Screen.DRAG` path: whole-word completion adds one correct count and rejected-letter retry does not persist a wrong count. Tower and Soccer retain per-letter correct/wrong evidence.

The Language-only state now persists product/profile scope, semantic content identity, originating activity and A-E stage, correct/wrong counters, current shared Parent word level, per-level consecutive passes, ramp, and applied evidence/pool IDs. Write evaluates only after its complete unique pool at 100/90%; Tower and Soccer evaluate only after complete bags at 600/80%. Two consecutive passing pools promote A→B→C→D→E once; failure resets the current-level streak; Manual, E, duplicate, and stale-level pools cannot promote. Counters and streaks survive mode switches/restart as Android does.

Promotion stores the shared Parent A-E value and ramp 90. Pool generation reproduces Android's independently rounded/capped previous/current list counts and shuffle; scene background maps `MainActivity.onStop` to a persisted -10 decay floored at zero. Plus/English Only remain product-isolated, learned language stays independent, and Math is untouched. Deterministic XCTest source covers the required 32 behaviors plus shared-counter/idempotency cases; focused negative/static audits run on Windows, while Xcode/XCTest and real background/restart validation remain pending. Status: `ANDROID_PARITY_IMPLEMENTED_SOURCE`. The remaining source unit is exactly the final Mixed/system review.

### 2026-09-07 — Final Language source parity / Mixed and system review

Starting HEAD: `ead1d811671beda171398220f81fda307cfc1127`. The current production route for all 13 child-visible Language identities, all activity release audits, all 16 canonical Android references, the complete Android Mixed owner path, Parent/settings, Auto, rewards/progress, speech/lifecycle/accessibility, English Only and Math isolation were reconciled without reopening accepted product decisions.

Mixed retains the exact repeating 20 Word-to-Picture / 10 Picture-to-Word / 5 Word Build schedule and activity-specific presentations. The typed session boundary now rejects advance callbacks from replaced child UUIDs as well as stale completion replacements; failed child construction remains atomic. Tests cover two complete cycles and stale callbacks. A typed eligibility mapper makes the existing Auto contract directly testable: only standalone Build completion maps to Android Write, Tower and Soccer attempts map to their own gates, and Mixed/other families return no Auto evidence. Choice/build rewards and `.mixed` telemetry remain unchanged and contain no Math fields.

The Auto audit now states the exact shared-hub architecture: Math currently receives an inert in-memory state load, but does not use, record, evaluate, promote, decay, or persist Language Auto state. Current source review found no remaining discoverable Language Android-parity discrepancy. `LANGUAGE ANDROID PARITY SOURCE GATE: ANDROID_PARITY_IMPLEMENTED_SOURCE`; separately, `RUNTIME_VISUAL_VERIFICATION_PENDING`. This is not release completion: Xcode/XCTest, device rendering and interaction, VoiceOver/Switch Control, RTL/Dynamic Type/Reduce Motion, speech/audio/timing, native-language QA, Phase 41 vocabulary/art, backend/leaderboard/services, commerce/policy/notifications, and TestFlight/App Store gates remain pending. No push or CI.

---

### 2026-09-08 — Phase 41 Android vocabulary asset reconciliation

Starting HEAD: `cdfe99e8e795732fb9f18851679d3103ed2f9876`. The preserved Phase 41 worktree was inspected without mutation. Exactly 397 previously approved `migrate_android` vocabulary rows were recovered as 397 isolated Xcode image sets and reconciled into canonical `main`; unrelated benchmark changes, a README deletion, and other dirty-worktree edits were not transferred. The migration preserves the manifest stable keys and bilingual English/Hebrew content, moves those rows from `missing_ios`/`migrate_android` to `existing_ios`/`reuse_ios`, and leaves the 33 `trusted_acquire` plus 101 `create_new` rows unresolved rather than fabricating art.

The checked-in migration report traces all 397 outputs to the existing Android drawable paths: 395 WebP sources and 2 PNG sources. The Windows-static audit verifies synchronized 543-row manifests, safe/unique identifiers, nonblank English and Hebrew values, source existence and byte counts, source/output dimensions, Xcode catalog references, and successful decoding of all 397 migrated PNGs. There is one byte-identical output pair, `cyan` and `turquoise`; their Android source files are themselves byte-identical, so the audit accepts the shared source provenance rather than treating it as an accidental iOS duplication. Current lifecycle counts are 409 `reuse_ios`, 0 `migrate_android`, 33 `trusted_acquire`, and 101 `create_new`. Xcode asset compilation and device visual review remain pending.

---

### 2026-09-12 — H1/H2 Firebase remote-records source integration

The Language products now link the official Firebase Apple SDK through Swift Package Manager and configure it only when a target-specific `GoogleService-Info.plist` is present. Missing configuration remains a supported source/test state rather than a launch crash. A Firebase anonymous-identity adapter and Firestore data source implement Android's existing app ID `3`, separate Plus/English Only score collections, shared streak collection, top-20 descending queries, legacy `date_achived` spelling, tolerant legacy-field defaults, tie/cutoff rules, same-player overwrite protection, and atomic merge writes. Math and Ping Pong do not link the Firebase products.

The Home trophy now opens a production score/streak leaderboard with loading, retry, not-configured, empty, and Firestore-cache/offline states. Deterministic XCTest source covers mapping, product isolation, ranking, identity/name behavior, and atomic schema writes. Windows source, localization, catalog-parity, test-source, and focused Firebase audits pass; XCTest/Xcode and real backend behavior have not run on Windows. Production Firebase plists, Firestore rules/index deployment, App Check and child-data/privacy review, reward-candidate submission wiring, and macOS/device validation remain release gates.

---

### 2026-09-12 — I1/I2 local learning reminders

First-release reminders are local-only; no FCM or remote-push dependency was introduced. They default off and can request alert/sound permission only after a parent enables the control in Parent Area. The production adapter uses one product-scoped repeating request at a conservative seven-day interval, cancels pending and delivered copies when disabled, repairs a missing opted-in schedule when the app becomes active, and never prompts during lifecycle restoration. Copy is privacy-safe and resolved using Minik's selected interface locale.

Deterministic XCTest source covers product-isolated persistence, cadence, contextual permission, denial, exact-once lifecycle repair, and cancellation. Focused notification, localization/catalog, product-policy, test-source, and diff checks pass on Windows. Real authorization, Settings revocation, delivery/timing, locale changes, and device lifecycle remain pending on macOS/device; the weekly cadence and copy remain explicitly subject to final product approval.

---

### 2026-09-12 — J2/J3 Minik commerce application integration

The existing reusable `AppStoreCommerceKit` package remains unchanged and is now linked into every target that compiles the shared app source. A thin Minik layer loads a per-target `MinikRemoveAdsProductIdentifier` Info value, maps only that non-consumable to the `remove_ads` entitlement, starts exactly one transaction-update listener at app startup, refreshes current entitlements at startup and foreground, supports explicit user restore, and persists only a product-scoped launch cache that is replaced by StoreKit's authoritative state. Missing product configuration leaves the app and Parent Area functional without fabricating an identifier or entitlement.

Parent Area presents StoreKit's localized price, purchase/pending/cancel/error/active states, and restore. Both StoreKit actions first require a randomized grown-up arithmetic gate; no purchase is exposed in a child activity. Deterministic app-layer XCTest source covers configuration, product isolation, startup listening/reconciliation, purchase, pending, update, restore, cache, and gate arithmetic. Focused commerce, localization/catalog, and test-source checks pass on Windows. Production App Store Connect non-consumable IDs, agreements/tax/banking/product metadata, StoreKit sandbox/TestFlight testing, and Xcode compilation remain external gates; the frozen hosted grace-period CI test was not run.

---

### 2026-09-12 — J4 child-directed ad boundary and cadence

Android's current `MyApp`, `InterstitialHelper`, `DeviceStatusManager`, `WriteScreen`, Tower, Picture Memory, Soccer and Tic-Tac-Toe sources were re-read as the shared-system authority. The iOS app now has a provider-neutral interstitial service and a product-scoped persisted policy. It preserves Android's no-first-opportunity behavior, shared `> 2` completion threshold, Picture Memory weight three, 60-second session warm-up, provider two-minute floor, current seven-minute interval and Android's persisted 7→5→4→3-minute background progression. Android WriteScreen opportunities cover standalone Picture→Word, Word→Picture and Build Word plus Mixed advances; Tower, Picture Memory, Soccer and Tic-Tac-Toe report only completed-round boundaries. Math curriculum routes do not inherit Language placement. Ping Pong reports only the existing owner-approved every-second completed-match opportunity.

Every provider configuration is forced to child-directed, under-age-of-consent, G-rated and non-personalized. `remove_ads` suppresses before counters or timestamps mutate. The app defaults ads and policy approval off and requires externally injected provider application/interstitial identifiers. No provider SDK was selected: until the App Store category/age band and a policy-compatible provider are approved, the production composition uses a no-op service and cannot display an ad. Deterministic XCTest source covers fail-closed configuration, safety flags, cadence/weights/warm-up, entitlement suppression, persistence, provider outcomes and the background interval floor. Focused ad, localization/catalog, English Only and test-source audits pass on Windows; XCTest/Xcode and real provider/device behavior remain pending.

---

### 2026-09-12 — J5 / Parent release-source completion

The Android Remove Ads reminder's exact durable timing contract is now represented: two days from first app observation, fourteen days after every presentation, one presentation per process session, immediate suppression for the permanent opt-out or Remove Ads entitlement, and no reminder unless both a real ad provider and a loaded StoreKit product are available. Deferral is persisted when the reminder appears so closing the sheet cannot create repeat spam. Its purchase action reuses the existing grown-up arithmetic gate and StoreKit controller.

Parent Area now exposes configurable HTTPS-only Privacy Policy, Terms of Use and Support destinations behind the same grown-up gate, optional configured legal notice content, and bundle marketing/build version. Empty or invalid external values remain visibly unavailable instead of falling back to invented URLs. Both catalogs validate at 561 keys across the existing 11 Full and 10 English Only locales; new non-English source fallbacks remain `needs_review`. Focused Parent/release, commerce, ads, localization/catalog, English Only and test-source audits pass on Windows. Xcode/XCTest, real external-link handoff, StoreKit, reminder presentation and accessibility/device review remain pending.

---

### 2026-09-12 — B5/H5 production reward coverage

The complete 13-route production Language inventory was compared with the Android reward reference and existing iOS event boundaries. Previously integrated choice/Build, Letter Pairs and Tower rules remain unchanged. The three documented source gaps are now wired: Picture Memory awards Android's fixed +2 per completed game without changing streak; Soccer awards +3 for a child win, +1 for a draw and no points for a loss; Tic-Tac-Toe awards +2/+1/-1 with the shared zero floor. Soccer and Tic-Tac-Toe emit typed final outcomes, and all new mappings reject Math and Ping Pong products.

On exit from a production Language activity, the current product-scoped aggregate points and best streak are submitted through the existing Android-compatible remote-record repository when Firebase is configured. Zero state, absent configuration and remote errors fail closed without changing local rewards. No Math reward values were invented, and Ping Pong remains without a reward policy because the inspected Android product has none. Deterministic XCTest source and a 13-route Windows audit were added; Xcode/XCTest, real Firestore writes, identity/name UX and new-record presentation remain pending.

---

### 2026-09-12 - N4/O1 release-configuration scaffolding

`project.yml` now exposes independent bundle-identifier overrides for all four applications and the test bundle, plus shared marketing/build version inputs and a final-app-icon name hook. The two Language targets accept an external `MINIK_FIREBASE_PLIST_PATH`; an empty setting remains compile-safe, while a configured build validates and copies that target's plist without committing account configuration. Final icons are not present and remain an explicit external asset rather than a fabricated placeholder.

Every application target now includes an app-owned privacy manifest. Language declares no tracking, app-only `UserDefaults` access using reason `CA92.1`, and the anonymous identity/gameplay record data sent by the current Firebase adapter for app functionality. Math and Ping Pong declare the same app-only defaults reason with no app-owned off-device collection. The source inventory found no implemented capability requiring an entitlement file; final signing, bundle IDs, icons, Firebase plists/App Check/backend rules, StoreKit/ad identifiers, public legal URLs, privacy decisions and App Store metadata remain external gates. `docs/release-configuration.md` is the configuration handoff, and the focused Windows audit validates the checked-in hooks and manifests. XcodeGen generation, archive privacy report, signing, macOS builds/tests and device/TestFlight validation have not run in this Windows unit.

---

### 2026-09-13 — Phase 41 vocabulary source-asset closure

The final 93 `create_new` vocabulary concepts were generated individually from the reviewed production queue and prompt-cell briefs. All outputs were visually inspected in labeled contact sheets; `snack_bar` intentionally remains the Android/Hebrew snack-counter sense (`מזנון`), and the potentially confusable Label, Museum Guide, Tour Guide, Ticket, Boarding Pass and Platform concepts retain their explicit visual distinctions. No vocabulary text, level, category, stable key, asset key, sampling rule, or activity behavior changed.

The generated importer records exact generation output IDs, prompt sources/sections, review dates, byte counts, SHA-256 hashes, decoded dimensions and actual alpha extrema, then copies byte-identical masters into isolated Xcode imagesets. The strengthened audit independently validates all 93 generated PNGs, the complete 543-row manifest, source/output provenance, unique generated hashes/output IDs, catalog references, and zero remaining `create_new`, `trusted_acquire`, or Android migration rows. Windows-static and visual-review gates pass. Xcode asset compilation, iPhone/iPad rendering and scale, VoiceOver context, native-language QA, TestFlight, and final human art-direction acceptance remain pending.

---

### 2026-09-13 — A2 GitHub-hosted four-product Simulator smoke gate

Status: completed at workflow/static level; first authorized manual macOS execution pending

Commit(s): checkpoint containing this entry, `checkpoint: add GitHub Simulator smoke gate`

Files changed: existing manual iOS Simulator workflow, deterministic workflow contract audit, Current Active Phase, Decision Log, and this Sprint Log entry

Tests run: directory-wide `.yml`/`.yaml` trigger audit; complete four-product/build-package/XCTest/runtime/artifact/final-verdict contract audit; Bash syntax parsing for all embedded workflow scripts; Python syntax parsing for both embedded evidence helpers; `git diff --check` and complete staged-diff review

Mac validation: not run. The next explicitly authorized manual dispatch must prove all four Xcode builds/packages, the single ProductConfigurationTests invocation, modern iPhone Simulator selection/boot, derived bundle identifiers, sequential install/launch/process survival/screenshots/logs/termination, crash collection, JSON summary, partial-success artifacts, and aggregate failure behavior.

Product decisions made by user: GitHub Actions only; no external validation service; manual dispatch only; mandatory complete four-product gate; one compile-gated XCTest pass; unsigned credential-free Simulator validation; no hosted AppStoreCommerceKit grace-period test; three-day evidence retention.

Reviewer result: workflow and Windows-static contract are prepared for review; no push or GitHub Actions run occurred, and no runtime success is claimed.

---

### 2026-09-13 — B5/H1–H5 public leaderboard privacy model

Status: completed at source/Windows-static level; macOS, deployed Firebase, device UX, and owner/legal review pending

Commit(s): checkpoint containing this entry, `checkpoint: implement public leaderboard privacy`

Files changed: typed curated alias and local state; consent-aware record submission/deletion; Firebase composition; child alias/pending UX; gated Parent disclosure/control/deletion UX; sanitized leaderboard presentation; deterministic tests; localization catalogs/sync; focused audit; release/privacy documentation and Living Status

Tests run: focused remote-records privacy audit; localization source/catalog audit; 592-key catalog validation for 11 Full and 10 English Only locales; reward-coverage, product-test-source and release-configuration audits; complete deterministic Windows audit/validator suite; `git diff --check`; complete staged-diff review

Mac/backend validation: not run. Xcode compilation/XCTest, production Firebase configuration, deployed rules/index/App Check enforcement, anonymous-auth lifecycle, real write/retry/delete behavior, child/Parent device UX, accessibility, and archive privacy reporting remain pending.

Product decisions made by user: the complete public leaderboard privacy decision recorded in the 2026-09-13 Decision Log entry

Reviewer result: source enforces no local-name path, no upload before persisted Parent approval, local best-candidate staging, stable curated alias reuse, immediate upload disable, and participant-scoped public deletion without local-progress mutation; legal text and backend policy remain explicit release gates.

---

### 2026-09-13 — B5/H1–H5 leaderboard alias activation adjustment

Status: completed at source/Windows-static level; macOS, deployed Firebase, device UX, and owner/legal review pending

Commit(s): checkpoint containing this entry, `checkpoint: remove mandatory leaderboard approval`

Files changed: participation preference/state and record-submission result names; immediate publish after first curated alias selection; direct Parent On/Off and deletion controls; deterministic privacy tests; localization catalogs/sync; focused audit; release/privacy documentation and Living Status

Tests run: focused remote-records privacy audit; localization source/catalog audit and catalog validation; reward-coverage, product-test-source and release-configuration audits; complete deterministic Windows audit/validator suite; `git diff --check`; complete staged-diff review

Mac/backend validation: not run. Xcode compilation/XCTest, production Firebase configuration, deployed rules/index/App Check enforcement, anonymous-auth lifecycle, real write/retry/delete behavior, child/Parent device UX, accessibility, and archive privacy reporting remain pending.

Product decisions made by user: the superseding public leaderboard alias-activation decision recorded in the 2026-09-13 Decision Log entry

Reviewer result: source enforces no remote access before curated alias selection, immediate pending publication after normal alias selection, no local-name/free-text path, stable alias reuse, persistent Parent opt-out, and participant-scoped deletion without local-progress mutation; legal text and backend policy remain explicit release gates.

---

### 2026-09-13 — O1 canonical Apple bundle-ID migration

Status: completed at source/Windows-static level; external registration, signing, Xcode generation, macOS builds/tests, and archives remain pending

Commit(s): checkpoint containing this entry, `checkpoint: migrate canonical Apple bundle identifiers`

Files changed: `project.yml` canonical defaults for four apps and test bundle; release audit forbidden-ID enforcement; README and release-configuration handoff; Living Status, Decision Log, and Sprint Log

Tests run: complete 37-entry Windows audit/validator suite; focused release audit requiring all five canonical identifiers and rejecting old/temporary identifiers in shipping Apple configuration; repository identifier inventory; `git diff --check`; complete staged-diff review

Mac validation: not run. XcodeGen-generated Info.plists, resulting `CFBundleIdentifier` values, unsigned Simulator builds/tests/smoke evidence, signing, archives, and App Store configuration remain pending.

Product decisions made by user: the five canonical production Apple identifiers recorded in the 2026-09-13 Decision Log entry; Android IDs and `remove_ads` remain unchanged

Remaining blockers: Apple Developer/App Store Connect registrations, matching Language Firebase Apple app registrations/plists, any approved AdMob iOS app registrations/IDs, signing, and macOS/archive validation

Reviewer result: prepared for review; no push, CI, or GitHub Actions run occurred

---

### 2026-09-13 — H1/O1 production Firebase plist wiring

Status: completed at source/Windows-static level; macOS build/runtime and deployed-backend validation remain pending

Commit(s): checkpoint containing this entry, `checkpoint: wire production Firebase Apple configuration`

Files changed: two target-specific production Apple Firebase plists; exact Language target paths and pre-copy `BUNDLE_ID` validation in `project.yml`; narrow ignore exceptions; deterministic release audit; release handoff and Living Status

Tests run: plist XML/bundle-ID inspection without credential output; target-path/isolation and single-initialization source inspection; complete 37-entry Windows audit/validator suite; `git diff --check`; complete staged-diff review

Mac/backend validation: not run. XcodeGen generation, plist copy phases, built-app resource inspection, Firebase initialization/authentication, Firestore rules/index/App Check behavior, all four builds, ProductConfigurationTests, Simulator smoke, signing, and archives remain pending.

Product decisions made by user: none; the previously confirmed canonical Language bundle-ID mappings were applied

Remaining blockers: Firebase Console/API restriction and deployed backend verification, App Check, legal/privacy approval, macOS/runtime validation, signing, and App Store release work

Reviewer result: prepared for review; Math/Ping Pong remain Firebase-free, Android configuration is untouched, and no push or GitHub Actions run occurred

---

### 2026-09-13 — H1 Firebase contract, Auth, App Check, and Rules readiness

Status: completed at source/Windows-static level; coordinated identity migration, deployment, macOS/runtime, and backend validation remain pending

Commit(s): `8000d0201c9782e5da1fad3fe245c544b5a14ab1` (`checkpoint: harden Firebase leaderboard readiness`)

Files changed: Android-derived cross-platform contract fixture and documentation; auth-gated iOS remote data source; anonymous UID/App Check bootstrap; Release App Attest entitlement; strict migration-target Firestore Rules/indexes/firebase configuration; deterministic remote-record tests and focused audits; release handoff and Living Status

Tests run: focused Firebase/remote-records/release/test-source Windows audits and `git diff --check`. XCTest was authored but not executed because no Swift/macOS toolchain is available on this Windows host.

Mac/backend validation: not run. The strict Rules were not deployed. Android production generates profile `player_id` independently of anonymous Auth and accepts legacy free-text `user_name`; current iOS also preserves a product/profile UUID. Secure `auth.uid` ownership therefore requires a coordinated Android/iOS identity and alias migration before Rules deployment.

Product decisions made by user: none

Remaining blockers: Firebase Anonymous Auth console enablement; coordinated participant/alias migration; rules/index deployment only after emulator testing; Apple/Android App Check registration and metrics; legal/privacy approval; macOS/device/backend validation

Reviewer result: source configuration is fail-closed, the migration/security consequence is explicit, and no backend deploy, push, CI, or GitHub Actions run occurred

---

### 2026-09-13 — N/O final Windows release-source closure

Status: all independently completable repository release preparation in this bounded pass is complete; Mac/Xcode runtime validation and owner console/legal actions remain

Commit(s): checkpoint containing this entry, `checkpoint: complete release source closure`

Files changed: known Google sample/test-ID rejection and deterministic test/audit; exact website privacy replacement, App Store privacy-data inventory, four-product Apple/Firebase/AdMob checklist, and expanded release handoff; explicit accessibility target fixes for Parent/Progress/Records controls; narrow accessibility/release-closure audits; Living Status and this Sprint Log

Tests run: complete 40-entry Windows audit/validator suite, focused new audits, `git diff --check`, staged checks, and complete staged-diff review. XCTest source was not executed because this host has no Swift/macOS toolchain.

Mac/backend validation: not run. Xcode generation/build/test, app launches, device App Attest/Auth/Firestore, StoreKit, ads, notification delivery, accessibility/runtime visual QA, archives/privacy reports, signing, TestFlight, and App Store submission remain pending.

Product decisions made by user: none; unresolved Kids/category, advertising enablement, privacy/legal classification, notification copy/cadence, and standalone Ping Pong commerce remain owner decisions

Remaining blockers: exact classified owner-console, legal/policy, and Mac actions are recorded in `docs/apple-release-checklist.md`; website privacy wording still requires approval/publication

Reviewer result: tracked source is prepared for the remaining external/runtime gates; the oversized pre-existing untracked rollout JSONL is untouched; no push, deploy, CI, hosted StoreKit test, or GitHub Actions run occurred

---

### 2026-09-14 — H1 secure multi-profile leaderboard ownership closure

Status: completed for canonical iOS source, Firestore Rules/configuration, deterministic Windows coverage, and migration handoff; Android implementation, administrator cutover, deployment, and runtime validation remain external

Commit(s): checkpoint containing this entry, `checkpoint: secure multi-profile leaderboard ownership`

Files changed: versioned per-product/profile participant identity; authenticated private ownership claim composition; ownership-gated record write/delete; strict ownership/public-schema Rules and contract fixture; secure migration runbook with exact Android file handoff; Parent curated change-alias control; privacy/release/Apple handoffs; deterministic tests/audits; Living Status and Decision Log

Tests run: complete 40-entry Windows audit/validator suite, focused Firebase/records/privacy/release/localization/test-source audits, JSON/XML validation, `git diff --check`, cached checks, and complete staged-diff review. XCTest source was authored but not executed because this Windows host has no Swift/macOS toolchain; Firebase Rules emulator execution remains an owner/backend prerequisite.

Mac/backend validation: not run. No Rules/index deployment, live-data read/write/delete, Auth/App Check console change, GitHub Actions, Xcode build/test, Simulator/device run, StoreKit host test, or external CI occurred.

Product decisions made by user: Firebase `auth.uid` must remain distinct from per-profile `player_id`; one UID may own multiple profile IDs; legacy IDs cannot be client-claimed; selected migration is administrator archive/verify/clear followed by strict Rules and coordinated updated clients

Remaining blockers: updated Android implementation in its owning read-only repository; Firebase Anonymous Auth and App Check registration; Rules Emulator Suite verification; administrator archive/clear/deploy cutover; policy/legal approval; macOS/device/backend runtime validation

Reviewer result: canonical iOS main is source-closed for this ownership model; the oversized pre-existing rollout JSONL and every Android reference file remain untouched; no push, deploy, CI, or hosted workflow occurred

---


## 2026-09-28 — Modern Ping Pong port, source implementation / pending Mac verification

Writable project: `C:\Projects\Minik-to-IOS\ios-main-merge`. Android reference: `C:\Projects\MinikPingPong` (read-only). New native engine/UI/services and current Android assets; scoped standalone root, target dependency/resource, audit and privacy handoff changes. Full/Simple capability boundary and host completion callback are implemented. Firebase Apple app `1:12298786440:ios:bfc268456a87978e75f13d` created for the existing `minikswish` backend. No production RTDB deployment/data edits, Git mutation, Pixels or ADB.

Validation: 43/43 isolated RTDB emulator tests pass; 152 Android/profile/asset/config source checks pass; staged Swift grammar parse passes; existing ads/commerce/release/product-configuration audits pass. Twenty-five focused XCTest methods were authored but cannot execute without Apple tooling. These checks are not a native build or proof of runtime parity. Release remains blocked on the documented Mac/iOS validation and App Store/production ads setup. Exact inventory and evidence: `docs/modern-pong-ios-handoff.md` and `docs/modern-pong-changes.json`.

## 2026-09-28 — Retro parity and shared Math/standalone entry

Status: implemented at source/Windows-check level; Apple build and runtime gates remain open.

Commits: repaired the moved iOS worktree link; Modern `b15717f`; following Retro commit titled `Share current Android 80s Pong gameplay across iOS Math and standalone`. Branch `main`, no push. Pre-existing untracked ZIP/oversized rollout excluded.

Files: exact inventory `docs/retro-pong-changes.json`; 73 provenance entries in `docs/retro-pong-android-provenance.json`. Shared bundled web engine/assets, narrow native lifecycle/storage/navigation host, Math chooser, new Retro target/icon, focused regression tests/audit and manual-only Apple workflow. Android, Firebase and existing Math curriculum/progress remain untouched.

Validation: 16 imported-engine checks, 7 JS bridge tests, 191 Retro checks, 152 existing Modern checks, four existing PowerShell audits pass; six Swift files grammar-parse without errors. Seven new XCTest methods authored, not run. Logs in `docs/retro-pong-evidence/windows-checks.json`. No native compilation, simulator, screenshots, physical device, StoreKit, ads runtime or live multiplayer verification; no available browser; no devices used.

Remaining: owner push/manual Apple workflow, iPhone/iPad English/Hebrew layouts and gameplay/audio/lifecycle, new standalone Apple registration/signing, and Modern’s separately recorded runtime gates. No Retro ads added; existing Modern test ads unchanged.

# PART XII — FUTURE SESSION BOOTSTRAP INSTRUCTIONS

A new ChatGPT or Codex session should be given this file and instructed:

> Read `ios/docs/MINIK_MASTER_PLAN.md` and `ios/docs/math-production-matrix.md` completely before proposing or editing production code. Treat CANONICAL PRODUCT CONTRACT sections as authoritative. Android is the reference for Language/shared Android behavior; there is no Android Math product. Math requirements come from the approved Math sections and user decisions. Inspect `AGENTS.md`, `ios/docs/android-known-fixes.md`, `ios/docs/reference/android-ui/README.md` and its 16 screenshots, `git status`, `git log`, recent commits affecting the feature, and the actual current contents of every file to be modified. Current newer behavior is authoritative unless an explicit user decision supersedes it; preserve features such as Tower speaker/replay and record newly approved behavior here instead of reverting it. Do not infer completion from enum counts or routes. Work one approved sprint at a time to its Definition of Done. After implementation, update only the Living Status, Decision Log (only for explicit user decisions), and Sprint Log without deleting product explanations. Never claim tests ran when they did not. ChatGPT/reviewer must inspect actual diffs/code before moving to the next sprint.

---

# PART XIII — REQUIRED DOCUMENT MAINTENANCE RULE

At the end of every approved sprint, Codex must:

1. update the sprint status marker;
2. update Current Active Phase;
3. append the Sprint Log entry;
4. append Decision Log only if the user made a new explicit product decision;
5. update the current commit/branch snapshot when material;
6. update completion estimate only after a major phase, not cosmetically;
7. never remove or summarize away the Android/product descriptions merely to shorten the file;
8. never mark an activity “complete” unless it meets the Definition of Done or the log clearly labels the remaining release blockers.

This document is intended to grow with the project. Its purpose is continuity, not brevity.

---

# APPLE REFERENCES CHECKED FOR THIS PLAN (2026-08-30)

Re-verify immediately before monetization/release implementation because policies/APIs can change:

- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Apple Kids guidance: https://developer.apple.com/kids/
- StoreKit `Transaction.currentEntitlements`: https://developer.apple.com/documentation/storekit/transaction/currententitlements
- StoreKit `AppStore.sync()`: https://developer.apple.com/documentation/storekit/appstore/sync()
- App Store Connect In-App Purchase configuration: https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases

---

**END OF CANONICAL MASTER PLAN — living snapshot updated 2026-09-28**
