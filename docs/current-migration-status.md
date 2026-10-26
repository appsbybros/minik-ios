# Current Migration Status

## 2026-10-26 sync (Minik Math Plus)

iOS Minik Math Plus now follows Android Minik Math Plus `7682b75..dc12a5c` (`ab3e427` and `dc12a5c`;
`e7fc548` is store/QA only and was skipped, as were play-store/, qa/, screenshots, version bumps and the
Android device tests). Type-checked only: on 2026-10-26 Windows Smart App Control blocked the Swift
6.3.2 `swift-frontend.exe` of `_work/swiftcheck`, so not even the Windows type check could run. Run the
iOS compile check and the ProductConfigurationTests before a build.

Ported:
- Every object fits its card (Android `countingGrid`): `MathQuantityLayout` (`Sources/MathQuantityFoundation.swift`)
  still shows all objects, smaller, in a card too small for its 18-point minimum, where it showed none.
- Visual → Answer counts a picture at every level (Android `pictureQuestion`): `MathPictureQuestions` in the new
  `Sources/MathLearningFeedback.swift`, used by the M2–M10 factories (`MathM2…M10ActivitySessionFactory.swift`):
  1–20 objects on levels 2–3, 1–30 from level 4, four numbers to choose from, behind each level's fit gate.
  Level 1 keeps its 0–10 questions. How to play: Android's new text.
- Math Cards: Android's sixteen rules with examples, four to a page, More facts for the next four; a tap marks the
  card and reads the rule and example aloud in the interface language (`Sources/MathCardsView.swift`,
  `MathRuleCard`). The activity is called Math Cards again (was Facts Table), with Android's subtitle; the hub's
  "Learn and review" subtitle now ends "then discover useful rules" (authored, `needs_review`).
- Math Soccer (`Sources/SoccerView.swift`, `MathSoccerShot`): a tap only chooses a ball; an upward swipe kicks it.
  The swipe's direction aims the kick and its speed sets the flight time (Android `soccerShot`); a goal needs the
  right answer inside the goal, a wrong answer inside is saved, a kick outside misses ("Outside the goal!").
  This replaces the random goal/save/miss outcome. VoiceOver: activating a ball, or the "Kick toward the middle
  of the goal" action, kicks straight. The letter soccer of the Language apps is unchanged.
- Build screens (`Sources/BuildView.swift`): a wrong Math answer clears itself after 0.8 s for another try
  (Android Build Math); with VoiceOver the Try again button stays.
- Hands-on examples (Android `needsDemo`/`DemoPrompt`, `Sources/MathActivityDemoView.swift`): the first opening of
  Build Number and of Math Soccer starts with one guided example, "Try one together", with Skip example. It records
  no answer, so no points, no level change, no daily or practice record. Soccer: Android's 1 + 1 with the balls
  1, 2, 3, a moving dot along an arrow up to the goal, until a goal. Build Number: 12 shown as one ten and two ones,
  tap 1 then 2 (iOS Build Number puts digits in order; this text is authored, `needs_review`). Remembered in
  UserDefaults `minik.math.demo-done.<activity>`.
- Practice history (Android `PracticeHistory`/`PracticeRecord`, `Sources/MathPracticeHistory.swift`): per scored
  activity and level, attempts, correct, completed rounds (a finished round or daily stage, once per opening) and
  the latest 20 answers (first answers; every matching attempt in Pairs and Memory), in UserDefaults
  `minik.math.practice-records.v1` in Android's line format. It starts empty: points, rewards, the level and the
  existing Progress & Statistics data are untouched and no earlier history is made up.
- Parent Area > Learning progress (Android `LearningProgressScreen`, `Sources/MathLearningProgressView.swift`, hub
  route `mathLearningProgress`): one suggested next activity (lowest recent accuracy under 80% at the current
  level, else the least practised) with Practice this activity, the newest six records (Show earlier practice),
  accuracy after five answers, completed rounds, and About this summary.
- Grown-up check (`Sources/ParentalGateView.swift`): the keyboard is dismissed before Continue or Cancel leaves.
- Texts: 47 new keys in both `Localizable.xcstrings` catalogs (All, and EnglishOnly without Hebrew, so the key
  sets stay equal for `Scripts/audit-localization.ps1`), Android's English and Hebrew; the other nine languages
  authored for iOS (`needs_review`).
- Tests: `MathLearningFeedbackTests.swift` (Android LearningFeedbackTest: cards never clip, a picture at every level,
  the swipe, plus the rules and the examples) and `MathPracticeHistoryTests.swift` (Android PracticeHistoryTest).

Deliberate differences:
- Not ported, because iOS Math is a different, per-level curriculum: Android's place-value Build Number (+/− tens
  and ones, 1–9 first then two-digit targets saved in `built_numbers`, 20 ones = 2 tens). iOS Build Number puts an
  answer's digits in order; iOS's place-value builder (Build Quantity, M4) keeps checking the tens/ones structure
  on purpose (`MathStructuredConstructionSessionTests`). Android's reusable Build Math tiles: iOS builds the whole
  exercise from pieces and already supplies a piece for each use. Android's five number-only towers before
  expression blocks: iOS towers never use expression blocks (count towers, or the answer's digits in order).
- The demo comes before the usual How to play card (first three openings) instead of replacing it, because the
  iOS card explains each level's own version of the activity.
- Soccer balls stay in their grid under the field (the iOS layout); a swipe is measured against the field's size
  and the ball follows the finger, where Android draws a line from a ball on the pitch. A shot outside the goal
  still scores for nobody (iOS SoccerSession), where Android gives the keeper the point.
- Already on iOS: speech in the interface language, Learn Math's Listen button, one hub column at large text sizes,
  48-point close targets, VoiceOver labels on the controls. Android-only and not ported: system-bar insets,
  Compose `fontScale` tweaks, `testTag`s and the "0" label on an empty picture.

## 2026-10-13 sync (Minik Plus, Minik Plus English, Minik Math Plus)

iOS now matches Android Minik `a4ea9be` and Android Minik Math Plus `7682b75` for what a child or
parent sees. Not compiled yet (no Swift toolchain on Windows); run the iOS compile check.

Ported:
- Minik Plus and English: daily learning (`Sources/MinikDailyLearning.swift`). A play that raises the
  playing child's points is one "little win", at most five a day per child and learned language
  (a per-child key in `ChildProfileStore`); the fifth shows Android's toast. Parent Area: a "Daily
  learning & feedback" button opens the daily page (progress, Back to learning, the family link,
  Rate / Share / Send feedback). Texts in the 11 Android languages.
- Minik Math Plus: the yellow "Daily math journey" entry on the hub and its page
  (`Sources/MathDailyJourneyView.swift`): ten scored activities in turn at the current level,
  3 / 4 / 5 correct first answers, 40 practice stars per stage plus 30 for the first stage of a day,
  a progress line above the activity. Parent Area: "Keep in touch" (Rate / Share / Send feedback).
  Hub: the "More below ⌄" cue under the panel while the board goes on below.
- Letter Soccer (2df3a2a): iOS already had the four lines and "More information" (9a14f62); the
  spoken intro now ends with Android's closing line ("Tap Start to begin. Good luck!").
- The interstitial family promotion and Remove Ads `ownershipResolved` were already on iOS (290f136).
- Tests: `Tests/ProductConfigurationTests/MinikDailyLearningTests.swift` (Android DailyLearningDeviceTest's
  counting rules and the Math journey's goals, stars and receipts).

Deliberate differences:
- Rate asks for the App Store rating prompt, Share sends the app's miniklearn.com page (no App Store
  link yet), and all three open behind the grown-up check (Apple's Kids rules).
- The Math daily page shows the activity's short description; the activity's own How to play card
  explains it per level. Math texts Android has only in English and Hebrew were authored for the
  other nine languages (`needs_review`).
- Not ported from Math Plus: the Parent Area entry as a #3F8CFF footer link (iOS keeps its header
  pill), the 24 dp section-heading inset (iOS section banners are the original), the scrollable
  activity frame for short landscape windows (Compose layout fix), the gate's LTR-isolated sum and
  white field (iOS uses a native form), the text-free launcher icon (iOS uses the store icon) and the
  AdMob removal (Android build configuration). Minik's "I have a code" link colour: iOS has no such link.

Status date: 2026-08-28. This resume note reflects the inspected repository rather than any historical phase label.

## Product and architecture

- The two primary outcomes are Minik language learning and Minik Math. `MinikPlus` remains the current language target/code name; no rename has been performed.
- Minik Plus English is a language-product policy variant with English fixed as the learned language, not a separate application architecture.
- `project.yml` defines one iOS 17 Swift/SwiftUI source base for iPhone and iPad, with `MinikPlus`, `MinikPlusEnglish`, and `MinikMath` targets selected through central `ProductConfiguration` policy.
- Language and Math share semantic content contracts and the reusable Learn, Multiple Choice, Build, Pairs, and Memory engines. Cards is currently language-facing; Tower and Soccer are currently Math-facing.
- Android remains the behavioral/content/product reference, but a concretely better native iOS/iPadOS convention takes precedence for presentation and interaction. Educational contracts are unchanged by that rule.

## Language activities already present

- The activity hub currently exposes letter Learn, Choose, Build, Pairs, and Memory plus word First Letter, Picture Starters, Word Build, Letter Pairs, Picture to Word, Word to Picture, Word Memory, and Word Cards.
- `LanguageActivitySessionFactory` connects those routes to shared session/view engines.
- Catalog-driven providers are present for alphabet Learn, multiple choice, build, matching, first-letter choice and picture activities, word choice, word build, letter pairs, word memory, and word cards.
- The normalized vocabulary loader validates and joins the packaged XML and image manifest into the runtime word catalog.

## Math state

- The Math hub currently exposes Learn, Choose, Build, Tower, Pairs, Memory, and Soccer through the same reusable activity UI where appropriate.
- `MathContentProvider` generates quantity, addition/subtraction, missing-addend, ordering, and equivalence content and supplies the specialized comparable, build, and soccer contracts.
- Current factory routes are an initial M1 quantity and M2 practice slice. Although the provider includes some M3 generation support and the architecture documents a provisional M1-M10 direction, the complete Math curriculum, adaptive orchestration, progress/persistence, and all later-stage content are not implemented.

## Vocabulary normalization

- Validation reports 1,270 generated entries across 142 arrays and 46 normalized categories: 955 lexical entries and 315 sentences.
- Final lexical counts are A 181, B 192, C 241, D 162, and E 179. Sentence counts are A 0, B 6, C 9, D 100, and E 200.
- Stable-key, schema, Unicode, collision, and XML/manifest metadata checks pass in `words-normalized-validation.txt`.
- Canonical docs and packaged runtime copies of both `words-normalized.xml` and `vocabulary-image-manifest.tsv` are byte-identical at this inspection.

## Image readiness and migration

- The manifest has 543 image-capable items: 12 `reuse_ios`, 397 `migrate_android`, 33 `trusted_acquire`, and 101 `create_new`.
- The 12 reusable assets are the only rows currently marked ready in iOS; 531 rows remain `missing_ios` by manifest lifecycle.
- All 397 Android migration rows resolve uniquely in `android/app/src/main/res/drawable`: 395 WebP and 2 PNG, with no missing, ambiguous, case-colliding, unsupported, vector, or XML assets.
- ImageMagick `7.1.2-29 Q16-HDRI x64` is available at `C:\Program Files\ImageMagick-7.1.2-Q16-HDRI\magick.exe`. Its format inventory reports WEBP read/write and PNG read/write support, and direct `identify` probes successfully decoded representative project WebP and PNG files.
- The 397 Android migrations have not been converted or added to the iOS asset catalog. No manifest lifecycle or resource files are changed here.
- Trusted acquisition and new image creation are intentionally later work.

## Reference correctness and working tree

- Always read `android-known-fixes.md` before reproducing Android behavior. Its intended behavior overrides the snapshot, currently including the Plus English learned-language initialization fix and Word Memory image-word pairing fix.
- The actual Git repository root is `ios/`; `C:\Projects\Minik` itself is not a Git repository.
- Before this documentation task, the iOS working tree contained one user-owned modification: `Tests/ProductConfigurationTests/LanguageWordContentProviderTests.swift`. It is preserved untouched.
- This task modifies `docs/product-architecture.md` and adds this status document inside the iOS repository. It also updates the workspace-level `AGENTS.md`, which is outside the iOS Git repository.

## Immediate blocker and next task

The earlier local-decoder blocker is cleared. The next implementation task is a separately authorized migration of the 397 resolved Android assets using the verified ImageMagick executable, followed by validation and manifest lifecycle updates. Do not start that migration merely from this resume note.

Still intentionally incomplete: the 397 Android asset conversions, the 33 trusted acquisitions, the 101 generated images, their manifest lifecycle updates, full production localization, persistence/adaptive progress, the full Math curriculum, and macOS/Xcode compilation and device validation.
