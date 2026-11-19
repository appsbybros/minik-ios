# Spud (Minik Amudu / מיניק עמודו) — iOS port handoff


## Deliberate difference: iOS payment model

Owner's decision (2026-11-19). Android Spud has ads and a "Remove ads" purchase; **iOS Spud has no ads** (no Google
Mobile Ads SDK, no ad code) and sells one non-consumable, `com.appsbybros.minik.spud.full_game` (Family Sharing on in
App Store Connect), through the shared `Packages/AppStoreCommerceKit` (StoreKit 2), as Minik Plus does. Owning it
unlocks everything. Without it:

| Limit | Rule | Where it is enforced |
| --- | --- | --- |
| Players | at most 3 in a game (the player + house players and/or people); 4-10 shown with a lock | `SpudAccess.clamp` / `playersLocked`; `AppModel.config(_:limited:)`, `spudPlayers`, `spudHouse`, `capacityNote`, `houseEnabled`, `setHouse`, `startLocal`, `openPrivateRoom`, `setupLeagueAction` |
| Arenas | Sunshine park only | `sceneLocked`; setup pictures (`chooseScene`), lesson conditions (`practiceConditions`: Andromeda = `.space`) |
| Balls | Soft foam and Beach ball; Neon party and Tennis ball locked | `ballLocked`; setup pictures (`chooseBall`), practice ball menu (`practiceBall`) |
| Paint balloon | 3 free welcome games, then 1 free game per local calendar day (no accumulation; the day the last welcome game is used counts as that day's game). Counted per game, never per throw | `PaintBalloonAllowance` (pure: stored state + date + calendar), `PaintBalloonAllowanceRepository` (`amudu.store.paintWelcomeUsed`, `amudu.store.paintFreeDay`), `SpudStore.usePaintGame`, `AppModel.spudMayStart`: a local match (`startLocal`), a hosted private room (`openPrivateRoom`, when the host opens it), a hosted league round (`setupLeagueAction`, purpose 2), a challenge or lesson run (`launchPractice`) |
| Daily challenges | steps 0-6 (challenges 1-7 of the first cycle) free; later ones show a lock and Start opens the unlock screen | `challengeLocked`; `AppModel.spudPractice` (from `launchPractice`), `PracticeOptions`, the challenge map |
| Lessons | same arena/ball limits; the paint lesson uses a free paint game | `spudPractice`, `PracticeOptions` |
| Online | only the host is limited: its room settings (capacity, arena, ball) apply to everyone, so joiners are never checked, whatever the host's platform, and a room opened from Android is never limited | `SpudAccess.limitsRoom`; `AppModel.openRoom` (`config(nil, limited: code == nil)`, the host's `spudHouse`), `setupLeagueAction` / `league.create` / `league.start`. No wire, protocol or database change: only the values the host writes |
| Old settings | a saved capacity (default 6), arena or ball is clamped at setup display and game start, never rewritten (`persist()` keeps the chosen values), so buying brings them back; resuming a saved game is allowed | `AppModel.config(limited:)`, `spudPlayers/spudScene/spudBall/spudHouse`, `PracticeOptions.init` |

Locked choices stay visible with "🔒 " and open the unlock screen (`SpudUnlockScreen`, an overlay in `RootView`, so
Back returns to the same page with its choices). The setup and practice pages show "N free paint balloon games left"
or "The next free paint balloon game comes tomorrow" while a non-owner has the paint balloon chosen. The unlock
screen lists what the full game adds, "One purchase, no ads. Family Sharing included.", "Unlock the full game · <App
Store price>" behind the grown-up gate, "Restore purchases" (no gate) and Back; owners see a thank-you state. States:
loading (disabled button, "Loading the App Store price…"), unavailable ("Load the price again"), purchasing/restoring
("One moment…"), Ask to Buy pending, cancelled (silent), failed, nothing to restore. `Transaction.updates` is followed
while the app runs: a Family Sharing grant unlocks, a refund or revoked grant relocks. Ownership is cached in
UserDefaults `amudu.store.fullGame` (offline launches stay unlocked). App Store captures (`SpudScreenshot`) count as
owned. Settings & feedback has an entry "Full game: unlocked ✓" / "Full game: not unlocked yet" (where Android's "Ads &
purchases" button would be).

Files: `Amudu/Store/SpudAccess.swift` (pure rules and the paint counter), `SpudStore.swift` (the AppStoreCommerceKit
controller), `SpudAccessModel.swift` (the `AppModel` extension the pages use), `SpudUnlockScreen.swift`,
`StoreText.swift` (the iOS-only texts in en, he, es, ar, hi, nl, with CLDR plurals for the paint line; not in
`AmuduCatalog.json`). `project.yml` links `AppStoreCommerceKit` to `MinikAmudu` and sets the Info.plist key
`SpudFullGameProductIdentifier` from `SPUD_FULL_GAME_PRODUCT_IDENTIFIER`. Hooks in Android-mapped files carry the
comment `// iOS payment model (CLAUDE.md): ...` (`UI/AppModel.swift`, `UI/Screens.swift`, `UI/GameScreen.swift`
`RootView`); a sync from Android must keep them. `Tests/AmuduTests/SpudAccessTests.swift` pins every limit, the
product ID, the texts, and fails if anything under `Amudu/` mentions the Google ad SDK or project.yml links it to
`MinikAmudu`.

When Android changes monetization (`monetization/*`, AdMob, Remove ads, access codes), do not port it; note it here.

## 2026-11-19 sync

iOS now matches Android `C:/Projects/MinikAmudu` commit **372c448** ("Refresh SPUD 0.29 store media and verify environment
learning layouts"); the whole `b07097c..372c448` range (about 60 commits, 2026-10-15 → 2026-11-18) of `app/src/main`,
`app/src/test` and `firebase/` was diffed file by file. The owner's uncommitted Android edits (version 0.30 in
`app/build.gradle.kts`, a `uses-feature` line in the manifest) are not part of the port; the SHA-256 table below lists
those two files at 372c448. Nothing has been compiled yet (no Swift toolchain on the Windows machine).

Ported, by area (Android → iOS):
- **Models and engine** (`core/*.kt` → `Amudu/Core/`): `Skills.jumping` and the new skill table (Moshiko is "קובי קפיץ"),
  the paint balloon ball (`BallKind.paint`), beach restitution 0.48 / tennis 0.82, the three controls
  (`ThrowMode` .easy "tap to throw" / .target "moving target" / .standard "Pro · swipe", Easy is the default),
  `NicknameAnswer` (choices / automatic / typed), `GameConfig.allowGroundHit / practiceLesson / callWindFactor`, duck
  height 1.4, `Member.points`, departures, elimination exits, burst flags on `Ball`, `GameCommand.pointThrow` and
  `throwBall(power:botVz:)`, `Words.proposalKey` (SHA-256) / `uniqueSuggestion`, new phrases. `AmuduEngine.swift` was
  re-ported from HEAD: catch timing and contacts (early catches judged against the released throw), attack heights,
  low gentle tosses, call lobs and wind paths (`callWindFactor`), round variety, bot ratings / Jump / name calls,
  penalty turn ownership (a miss gives the turn to the thrower), recall and elimination, swept movement without jitter
  at boundaries, stationary holders, bots returning to their circle spot, paint balloons with burst cycles and splashes,
  retrieval grace, nickname proposals. New files, one per Kotlin file: `ActorMovement`, `AttackPhysics`, `BallContact`,
  `BallShadow`, `CallLob`, `CatchPhysics`, `CircleFormation`, `EliminationExit`, `FleeMovement`, `GroundBounce`,
  `PaintBalloon` (+ `PaintSplash`, `BalloonBurstCycle`), `PracticeCurriculum` (+ `PracticeConditions`),
  `PracticeGuidance`, `TargetThrow`, `TossGesture`. `KotlinCompat` gained `nextInt(from:until:)`, `nextBoolean()` and
  Kotlin's `shuffled` order.
- **Journey and learning** (`SpudJourney.kt`): 40 challenges (base stages + inserted environment variants), `DrillSkill.tag`,
  stage keys, mastered set and the one-time migration of saved progress, `SpudPractice(step, seed, lesson)` with
  point throws, paint impacts and partner misses; the lesson hub (controls, balls, wind, gravity, ground rule, paint,
  calls, stop, match rules), challenge map with replays, practice options (controls, ball, conditions, ground rule).
- **Codec** (`Codec.kt` → `AmuduCodec.swift`): every new member/config/snapshot/actor/ball/practice field, burst cycles,
  paint splashes, the `readConfig` migration, `consumed` as a map, the `pointThrow` command.
- **Online** (`OnlineRoom.kt`, new `MotionState`, `SnapshotPlayback`, `SnapshotWire`, `OnlineErrors`, `LagDiagnostics`,
  `FamilyLeague` → `Amudu/Online/`): delta snapshots with motion publication (`motionProtocol` 4, `gameProtocol` 2,
  `controlsRevision` 2), remote flight continuity and burst state during playback, push-key commands flushed at once
  except move/aim, presence re-registered after reconnects, departures (`left`), start without unready players,
  expired/finished/removed rooms, unique bot words, early huddle finish, `word_<sha>` proposals, the opt-in lag
  diagnosis, and **private family leagues** (`leagues`, `leagueCodes`, `leagueUsers`, `leagueInvites`; standings,
  rounds, pending results kept in UserDefaults `amudu.league-pending`) with the league page `FamilyLeagueScreen.swift`.
  Same RTDB paths, field names, value types and write order as Android.
- **Arena** (`AmuduView.kt` → `Game/ArenaView.swift`, new `Game/PaintEffects.swift`, `world/*` → `World/`): tight and
  airborne framing (`TightFraming`, `AirborneFraming`), the attack/target cameras, the tap-to-throw and moving-dot
  target controls (4-point homography like `Matrix.setPolyToPoly`), toss power from the swipe, catch/jump/duck action
  bar, paint on players (face kept clear), ground splashes, footprint shadows, hidden burst balloon, elimination walk-out,
  held ball on the palm, two-line name tags with the yellow selected-caller tag, RTL-mirrored HUD, compact HUD label
  spacing, lesson status/instructions, beach sand shader, `ProjectileText` ("balloon" wording with the paint balloon).
- **Screens and dialogs** (`AmuduActivity.kt`, `ui/*`, `SelectionWidgets`, `PictureChoices` → `Amudu/UI/`): the unified
  SPUD dialog (`UI/SpudDialog.swift`: pale panel, pink ×, mint Continue, sky actions, pink negatives) replaces the iOS
  system alerts (pause, nickname, phrases, join, share, feedback, lobby checks, league join/delete); the shared localized
  grown-up gate card; header back arrow; centred dropdown lettering and RTL caption; raised-button lettering on the
  full raised face (`FamilyKit.Lettering.fullRaisedFace`); setup capacity line, house players limited to free places
  with Jump rating, "Answering nicknames" and "Ground contact before a hit"; lobby portraits, stars, points, stale
  confirmations dismissed when readiness changes or play starts; nickname huddle with target, preview and own-vote
  mark; pause actions (lesson / challenge / game wording, Exit for guests); results title and winners line; Back to
  league; phrases only when a voice exists for the app language.
- **Art and audio**: `atlas.json`, `directions.json` and the new `face-protection.json` copied unchanged to `Amudu/Art/`;
  new `paint_balloon_menu` and `practice_tree` image sets (PNG, pixel-identical to the webp); new
  `amodu_call_female.mp3` (Hebrew Amodu call for Kyra, Gaya, Mia, Amber and June) and `balloon_burst.mp3` in
  `Amudu/Audio/`.
- **Texts**: `AmuduCatalog.json` regenerated (1142 rows: `+ spudNovemberText + spudMonetizationText +
  spudNovemberReviewText + spudEighteenIssueText + spudTargetText + spudLearningText`); generated from Kotlin:
  `Text/LearningCopy.swift`, `Text/EnvironmentCopy.swift`, `Text/SpudFollowupText.swift` (joined before the GameText
  overrides); `Text/ProjectileText.swift`; `AppText.t` translates multi-line texts line by line like Kotlin.
- **Firebase**: `Tests/AmuduFirebase/database.rules.json` and `rules-test.cjs` refreshed byte for byte; the local
  emulator run passed 196, failed 0, 0 production writes.
- **Audit**: `Scripts/audit-amudu.py` reads `spudLearningText`, audits the new Kotlin files, checks the new assets, and
  lists the Android-only literals (`ANDROID_ONLY_2026_11`). Result: catalog identical, overrides identical, 0 literals
  missing, assets OK (the only hygiene notes are CRLF in the Windows working tree from `core.autocrlf`).

Deliberate differences:
- **Monetization (not ported; iOS has its own payment model, see "Deliberate difference: iOS payment model" above)**.
  Android now has: an "Ads & purchases" home button behind the
  grown-up gate; a page with the 3-day ad-free welcome and days left, "Ads removed until {date}" / "permanently",
  "Remove ads · price" (Google Play one-time product `remove_ads`, option `remove-ads-option-id`), "Restore purchase" with
  its states (loading, not owned, verifying, pending, cancelled, verification failed); "Enter code": MINIK's existing
  Firestore promo codes (`access_tokens`, matched on `token` and `app_id` "8", fields `is_active`, `expires_at`,
  `num_of_free_days_from_entering_token`, `already_installed_stays_with_token_always`, `access_type`,
  `max_uses_per_token`, `num_of_tokens_already_used`, per-user claim `access_tokens/{id}/claims/{uid}`, a separate
  Firebase app "spud-access-codes" with App Check) whose only effect is removing ads for N days or permanently, stored as a
  Keystore-signed record; re-checks on foreground; AdMob interstitials after completed games (not during the 3-day
  welcome, at most every 4 minutes); the family remove-ads reminder (first idle launch, then every 14 days). On iOS there
  are no ads, so codes and Remove ads would unlock nothing; none of it is ported and the page stays hidden.
- **Speech failures**: Android disables phrases after an asynchronous TTS engine error; AVSpeechSynthesizer reports no
  such error, so iOS only checks up front that a voice exists for the app language.
- **Privacy policy page**: built (with the grown-up gate on its links). Since 2026-11-19 the iOS policy is bundled as
  `Amudu/Privacy/privacy-<language>.html` (six languages; the `appstore/privacy/Spud/` pages without their language links),
  so the home menu shows "Privacy policy". Android's text describes the Android app (AdMob, Google Play, Android storage)
  and is not ported; when the iOS policy changes, update `appstore/privacy/Spud/`, these copies and the website copies
  together (`docs/amudu-app-store-submission.md`).
- **Lag diagnosis**: iOS omits Android's `android` (SDK level) field (the rules reject unknown fields); `model` is "Apple " +
  the hardware id, `code` is `CFBundleVersion`.
- League page without Firebase shows "Online activation is pending." (Android shows a blank page). League rows, round order
  and bot huddle-suggestion order follow UTF-16 key order (Android HashMap order); the checkpoint's `consumed` map is read
  in sorted key order.
- Dropdown lists open as the iOS system menu; button lettering sits about 0.9 pt below Android's exact centre; the paint
  mask is scaled without interpolation (Android's unfiltered `drawBitmap`), so patch edges can differ by about a pixel.
- Debug/QA only, not ported: `controlBounds`/`tagBounds`/`qaCapture`, test tags, the emulator and `qaRemote` Firebase apps.

Skipped: Play Store material, `website/`, `tools/privacy`, Gradle/version, BUILD_STATUS-style notes, the instrumented
device tests (`androidTest/*DeviceTest`) and the monetization JVM tests (`AdPolicyTest`, `AccessTokenRulesTest`,
`EntitlementStoreTest`, `PlayOwnershipStoreTest`, `PlayPurchaseProcessorTest`, `PurchaseOptionSelectorTest`).

Android behaviour ported as-is that may be unintended (reported to the owner):
- `readConfig` always loads `FreezeRule.FREEZE` and `canRun` no longer honours HONOR: Honor rooms and saved games now play
  as Freeze (the setup no longer offers Honor).
- In `Throw`, `idleStrikes = 0` and `stepRemaining = 0` run before a human command carrying `botVz` is rejected.
- `PracticeCurriculum.recommendedBall` ignores its step argument; `SpudPractice.incoming` has an unused `bots` local.
- `FamilyLeague.isHost` is `uid == id`, true while both are still empty; `recordOffline` is never called on Android.
- In `MotionState`/`SnapshotPlayback` the facing check `next.length() < .01` can never be true (`unit()` never returns a
  short vector).
- The host's alone-with-house-players start calls `now()` twice (seed and id can differ).
- `PaintEffects.ground` droplet radius is in raw pixels (iOS converts with `1/displayScale`).
- Any dialog button whose text equals the translated "Back"/"Cancel" turns pink; "Wait" in the lobby check stays pink.

Tests: new XCTest files with Android's seeds and expected values — `NovemberMovementTests.swift`
(AttackHeight, BlockedMovement, CircleMotion, FollowupPhysics; 28), `NovemberRoundTests.swift` (RecallAndElimination,
ReturnMovement, RoundVariety, EighteenIssueRegression, EnvironmentFeedback; 34), `BalloonTests.swift` (BalloonCadence,
CatchBurstRules, TargetBalloon; 19), `LearningTests.swift` (BotCallAndTurn, LearningCurriculum, OwnerFeedbackPhysics,
SpaceToss; 28), `OnlineNovemberTests.swift` (LeagueStandings, MotionState, SnapshotWire, NovemberNetworkRegression; 15),
`NovemberTestSupport.swift` (helpers and a `java.util.Random` port for BlockedMovementTest); AirborneFraming added to
`WorldTests.swift`; the female-voice cases to `RanksVoiceAndCourtTests`. Existing ports follow Android's updated
expectations (AmuduEngine, Revision, OctoberRefinement, GameRules, SpudJourney with 40 stages, ProtocolTests' field and
wire-name lists, which now include all 11 phases). Deviations: Kotlin's shared `Ball` object identity (`===`) is matched by
flight id in `OwnerFeedbackPhysics.failedPassIsStillInFlightBeyondReceiver`; `SpudStage` is compared by `id`; loops that
wait for a phase change have guards so a regression fails instead of hanging; `DeviceEquivalentTests`'s held-catch test
no longer sends a Move (a Move now cancels a prepared catch, as on Android).
Checkpoint round trips that compare actors by index pass the roster order (`create(_:order:)`, like the saved local game),
because Kotlin's in-memory map keeps it and a Swift dictionary does not; the nickname target's instruction is checked
against Android HEAD's "The other players are choosing a nickname for you." (Android's DeviceInteractionTest still expects
the older "Take a break"); `LanguageTests` pins the 1142 catalog rows.

Least-sure compile spots (2026-11-19 additions):
- `Amudu/Core/AmuduModels.swift:670` — default on an enum associated value (`throwBall(power:botVz: Double? = nil)`);
  CryptoKit `SHA256.hash(data:)` in `Words.proposalKey`. `Amudu/Core/PaintBalloon.swift` — the backticked `` `throws` ``
  property and the `[Int64 literal].map { (value: Int64) -> Int in … }` colour table.
- `Amudu/Game/ArenaView.swift:1239` (`beginTransparencyLayer(in:auxiliaryInfo:)` inside save/restore), `numericCast`
  into `Int64` parameters; `Amudu/Game/PaintEffects.swift:106/144` (`withUnsafeMutableBytes` closures, one returning
  `CGImage?`).
- `Amudu/Online/OnlineRoom.swift:368/417/619/960` and `Amudu/Online/FamilyLeague.swift:246/284/354` — Firebase completion
  and transaction blocks inside synchronous closures and `Task`s, `[String: Any]` → `[AnyHashable: Any]`;
  `Amudu/Online/SnapshotWire.swift:24/32` metatype checks; `Amudu/Online/LagDiagnostics.swift` (`utsname` bytes,
  `assumeIsolated`); `Amudu/Online/FamilyLeagueScreen.swift:96` (SwiftUI `Grid`).
- `Amudu/UI/SpudDialog.swift:82-84` (title/action tuples with `@MainActor` closures) and its callers in `AppModel.swift`;
  `Amudu/UI/Screens.swift:622-637` (`WKNavigationDelegate` coordinator); `Amudu/UI/AppModel.swift:283`
  (`FamilyKit.Lettering.fullRaisedFace`, a `@MainActor` static set from `AppModel.init`).
- Tests: `XCTAssertEqual(try …, try …)` and `try` inside `map` closures (`NovemberRoundTests.swift`), tuple arrays of
  `GameCommand` (`NovemberMovementTests.swift`), `AmuduCodec.config(try GameConfig(practiceLesson:))` inside an assertion
  (`ParityAndProtocolTests.swift`).

## 2026-10-13 sync

iOS now matches Android `C:/Projects/MinikAmudu` commit **b07097c** ("Improve SPUD skill journeys, camera assistance
and tournament menus", clean tree) and, for the shared menu look, `C:/Projects/MinikFamilyServices` commit dcfdd13. The
real change since the 2026-10-12 state was in `AmuduActivity.kt`, `PictureChoices.kt`, `SelectionWidgets.kt`,
`ui/GameDialogBuilder.kt` and the family classes they now use (the SHA-256 table below is regenerated).

Ported:
- Hebrew texts: "Daily skill journey" is "אתגר יומי"; "Ball approach zoom" and its two switches say "מיקוד המצלמה …".
- Private room lobby: when you are the only human (the rest are house players), every line says "Not started" and the
  Ready button is gone; the host's Start is unchanged. Online protocol untouched.
- Raised "sky" surfaces (`FamilySkyDrawable`, new `UI/SkySurface.swift`): every page button, section button, setup
  group toggle, choice field, picture card and result row; pressed controls sink into their edge.
- Home menu (`FamilyMenu`): sections are pale sky panels outlined in their colour, with dark headings and the 6 dp
  heading inset; the profile texts use the menu ink; the name field is the white `FamilyFormStyle` input; colour-rank
  labels (home and rank page) are flat with 8 dp corners; avatar arrows are the raised teal chevrons.
- "More below ⌄" cue under the home menu (`FamilyMoreFrame`): reserved 48 dp strip, shown while more lies below,
  bouncing unless Reduce Motion or VoiceOver is on; a tap scrolls 65% of the visible height.
- Pages use `FamilyReadingPanel` (a centred column of at most 520 dp in landscape, e.g. the landscape result page).
- App-drawn dialogs (players & scores, return vote, nickname huddle) are white sky panels with 24 dp corners; their
  Continue is a raised sky-blue button; the huddle word field is the white input.
- Landscape hint (`FamilyLandscapeHint`): a game that opens in portrait shows "For a wider view, play in landscape."
  after 0.9 s.

Deliberate differences:
- The pause, nickname, join, grown-up gate, share and feedback dialogs stay iOS system alerts (not restyled).
- The home rank label keeps its rank ink; Android paints a Blue/Brown rank label in menu ink until the avatar changes.
- "More below", its spoken label and the landscape hint come from `FamilyMessages.text`: Hebrew and English now, the
  other languages once the shared `Family/FamilyText.swift` has those three rows.

Skipped: Play Store material, `BUILD_STATUS.md` notes, Gradle/versionCode, and the new device-QA tests
(`setupqa/FamilyMenuReviewDeviceTest`, `MenuDiscoveryDeviceTest`, `MenuFormsDeviceTest`, `SkyMenuCaptureTest`).

## Re-sync of 2026-10-12

iOS matches Android `C:/Projects/MinikAmudu` at HEAD 2749a49 **plus its uncommitted 2026-10-10/11 work** (the daily
skill journey). The exact Android file states are the SHA-256 table at the end; `port_drift`-style checks compare it.

- 37e1d4a → 2749a49 (rule sets, spectators, timers, return votes, shared pause, step allowance, colour ranks, wider
  courts, world renderer, stable labels, landscape layout): engine/models/codec were ported first (branch
  `wip/spud-splash-port`), the screens, dialogs, stop-call recordings, online changes, tests, icon and names now.
- Daily skill journey (Android uncommitted): `Core/SpudJourney.swift` (30 challenges, cycles, `SpudProgress` points and
  daily bonus, `BallFlight`, `SpudPractice` judged by real ball contacts), jump, `challengeStep`, the practice wire
  state, the journey pages and celebration, the practice camera/targets/cues/Jump button in the arena.
- Ball approach zoom (`World/SpudReceptionZoom.swift`) with its two switches on Settings & feedback, Game sounds switch,
  Settings & feedback behind the grown-up gate, colour-rank page, home sections, launcher icon and "Minik …" names.

Source: Android project `C:/Projects/MinikAmudu` (read-only; state of 2026-10-12). Target: XcodeGen app `MinikAmudu`
(`Amudu/**`, bundle `com.appsbybros.minik.spud`, display name per language) and test target `AmuduTests`.

## Status

- Full behavior port of every screen, the game rules, controls, house players, sounds, speech, saved games/settings,
  six languages with RTL, localized app names, and the private-room Realtime Database protocol.
- The Swift has **not been compiled** (no Swift toolchain on the Windows machine). It was written against the iOS 17 SDK
  and Swift 5.9 and re-read line by line; see "Least-sure compile spots" before the first macOS build.
- Ads, purchases and code redemption are off (no AdMob, UMP or purchases); Android's "Ads & purchases" button is hidden.
  StoreKit is used only for the App Store rating prompt ("Rate the app").
- Online rooms activate only when this app's `GoogleService-Info.plist` (bundle `com.appsbybros.minik.spud`, with a
  `DATABASE_URL`) is bundled. Without it, "Join by code" and "Open private room" show Android's
  "Online activation is pending." and everything else runs offline.

## Android file → iOS file

| Android | iOS | Notes |
|---|---|---|
| `core/Models.kt` | `Amudu/Core/AmuduModels.swift` | `Scene`→`ArenaScene`, `Actor`→`GameActor`, `Character(s)`→`AmuduCharacter(s)`, `Event`→`GameEvent`, `Command`→`GameCommand` (Swift/SwiftUI already own those names). Enum raw values are the Kotlin enum names (wire format). |
| `core/AmuduEngine.kt` | `Amudu/Core/AmuduEngine.swift` | Statement-by-statement port: same physics constants, same order of random draws and floating-point operations; `step` split into helpers without reordering. |
| (kotlin.random, Java) | `Amudu/Core/KotlinCompat.swift` | Exact `kotlin.random.Random(seed)` (XorWow), Java `String.hashCode`, `Math.floorMod`, Kotlin trim/isBlank/`toInt`, UTF-16 string order, stable sort, insertion-ordered map/set (`linkedMapOf`, `LinkedHashSet`). |
| `Codec.kt` | `Amudu/Core/AmuduCodec.swift` | Identical field names; NSNull for Kotlin `null`; Booleans and numbers kept apart like Kotlin's `as? Number` / `as? Boolean`. |
| `localization/AppText.kt` | `Amudu/Text/AppText.swift` + `Amudu/Text/AmuduCatalog.json` | All 1142 rows (959 before 2026-11-19) in Android's effective order (`es, ar, hi, nl` columns), regenerated by `Scripts/audit-amudu.py`'s Kotlin reader; `{0}` templates matched like Kotlin (longest key first). |
| `GameText.kt` | `Amudu/Text/AppText.swift` (`GameText`) | Names, stop calls and the 14 branding overrides verbatim. |
| `ArtStore.kt` | `Amudu/Art/ArtStore.swift` | Same frame selection, facing, mirrored side art and 256x320 hand anchors. |
| `AmuduView.kt` | `Amudu/Game/ArenaView.swift` | UIKit view: arena picture in a `UIImageView`, every frame drawn with Core Graphics (the same immediate-mode drawing as Android's Canvas), `CADisplayLink` loop, identical touch arbitration. |
| `SelectionWidgets.kt`, `PictureChoices.kt`, `JourneyCelebration.kt`, `ui/*` | `Amudu/UI/Widgets.swift` | `SkillStars`, `AvatarArrow`, spinner (`ChoiceMenu`), `PictureChoices`, group toggle (`CenteredToggleSpan`), switches, dialog card (`GameDialogBuilder` colours), celebration, buttons, labels, page scaffold, toast. |
| `core/SpudJourney.kt` | `Amudu/Core/SpudJourney.swift` | `DrillSkill.CATCH` is `.catching`; Kotlin's shared `Ball` objects become a `PracticeBall` that owns its ball (the engine ball is refreshed from the first shot every tick, as Kotlin does). |
| `core/ProgressRanks.kt` | `Amudu/Core/ProgressRanks.swift` | Colour ranks and `RewardLedger`. |
| `RuleText.kt` | `Amudu/Text/RuleText.swift` | All six-language rule texts. |
| `StopCallVoice.kt`, `HebrewStopCalls.kt` | `Amudu/Game/StopCallVoice.swift` | The two Hebrew recordings, preloaded AVAudioPlayers, one at a time. |
| `world/*` (`ArenaCamera`, `LandscapeFraming`, `SpriteSizing`, `StableLabels`, `ArenaWorldView`, `SpudReceptionZoom`) | `Amudu/World/*` | The OpenGL ES world is Metal (same shader math); `onFirstFrame` included. |
| `localization/GameSupportText.kt`, `SpudJourneyText.kt` | `Amudu/Text/AmuduCatalog.json` | Part of the 959 catalog rows. |
| `AmuduActivity.kt` | `Amudu/UI/AppModel.swift`, `Amudu/UI/Screens.swift`, `Amudu/UI/GameScreen.swift`, `Amudu/AmuduApp.swift` | Screens, settings, dialogs, saved game, event sounds/speech, lifecycle. |
| family `FamilySkyDrawable`, `FamilySkyUi.dialog`, `FamilyFormStyle`, `FamilyReadingPanel`, `FamilyMoreFrame`, `FamilyMenu.section/style` | `Amudu/UI/SkySurface.swift`, `Amudu/UI/Widgets.swift` | The Spud-side look only (`SkySurface`, `SkyButtonStyle`, `InputFace`, `ReadingPanel`, `MoreBelowCue`, `MenuSection`); the shared `Family/` module has no surface API. |
| `OnlineRoom.kt` | `Amudu/Online/OnlineRoom.swift` | Same RTDB paths, transactions, lease/host takeover, 12 Hz snapshots, command queue, huddle protocol. |
| `core/ActorMovement.kt`, `AttackPhysics.kt`, `BallContact.kt`, `BallShadow.kt`, `CallLob.kt`, `CatchPhysics.kt`, `CircleFormation.kt`, `EliminationExit.kt`, `FleeMovement.kt`, `GroundBounce.kt`, `PaintBalloon.kt`, `PracticeCurriculum.kt`, `PracticeGuidance.kt`, `TargetThrow.kt`, `TossGesture.kt` | `Amudu/Core/<same name>.swift` | 2026-11-19; Kotlin `object` → Swift `enum` with static funcs, same names. |
| `MotionState.kt`, `SnapshotPlayback.kt`, `SnapshotWire.kt`, `OnlineErrors.kt`, `LagDiagnostics.kt`, `FamilyLeague.kt` | `Amudu/Online/<same name>.swift`, `Amudu/Online/FamilyLeagueScreen.swift` | 2026-11-19; same RTDB paths as Android's rules. |
| `PaintEffects.kt` | `Amudu/Game/PaintEffects.swift` | Paint on players, ground splashes, balloon art. |
| `world/AirborneFraming.kt`, `world/TightFraming.kt` | `Amudu/World/AirborneFraming.swift`, `TightFraming.swift` | |
| `ui/SpudDialogStyle.kt`, `ui/GameDialogBuilder.kt`, `ui/SpudSpinnerAlignment.kt`, `ui/SpudPresentation.kt`, family `FamilyButtonAlignment` | `Amudu/UI/SpudDialog.swift`, `Amudu/UI/Widgets.swift`, shared `FamilyKit.Lettering.fullRaisedFace` | One SwiftUI dialog card replaces the system alerts. |
| `localization/LearningCopy.kt`, `EnvironmentCopy.kt`, `SpudFollowupText.kt`, `ProjectileText.kt` | `Amudu/Text/LearningCopy.swift`, `EnvironmentCopy.swift`, `SpudFollowupText.swift`, `ProjectileText.swift` | The first three are generated from the Kotlin rows (all six languages). |
| `localization/SpudNovemberText.kt`, `SpudNovemberReviewText.kt`, `SpudEighteenIssueText.kt`, `SpudTargetText.kt` (+ `spudMonetizationText` in `AppText.kt`) | `Amudu/Text/AmuduCatalog.json` | Part of the 1142 catalog rows. |
| `AmuduAds.kt`, `monetization/*.java` | — | Not ported (ads and purchases off on iOS). |
| `res/raw/*` | `Amudu/Audio/*` | Copied unchanged (all 14 files since 2026-11-19, with `amodu_call_female.mp3` and `balloon_burst.mp3`; including the two Hebrew stop calls; `sfx_hit.mp3` is unused on Android too). |
| `assets/art/*.webp`, `tennis.png` | `Amudu/Assets.xcassets/<name>.imageset` | Decoded and re-encoded as PNG, pixel-identical (verified by decode comparison); 1x only, so frame crops use the atlas pixel rectangles. |
| `assets/art/atlas.json`, `directions.json`, `face-protection.json` | `Amudu/Art/` | Copied unchanged. |
| `res/values*/app_name.xml` | `Amudu/{en,he,ar,es,hi,nl}.lproj/InfoPlist.strings` | `CFBundleDisplayName` = Android `app_name` per language. |
| launcher icon (`launcher_foreground.xml`, `minik_spud_launcher_glow.webp`) | `Amudu/Assets.xcassets/AppIcon` | 1024 px from the 2026-10-06 master (`art/launcher/2026-10-06-padding/generated-master.png`, which downscales exactly to the webp): the part an adaptive icon shows, i.e. the central 72/86.4 of the 10 % inset image. |
| `firebase/*` | `Tests/AmuduFirebase/*` | Byte-identical reference copies plus README. |
| `src/test/**`, `src/androidTest/**` | `Tests/AmuduTests/*` | See Tests. |

## Behavior decisions

- **Language**: Android uses the phone's first language (`resources.configuration.locales[0]`), normalized to
  en/he/es/ar/hi/nl (else English; `iw`→`he`). iOS uses `Locale.preferredLanguages.first`, which also reflects the
  per-app language chosen in iOS Settings. Hebrew and Arabic switch the menus to right-to-left; the avatar row stays
  left-to-right as on Android; the arena is drawn in absolute coordinates.
- **Texts**: every user-visible and protocol literal of the Android Kotlin sources is present verbatim in Swift
  (checked by `Scripts/audit-amudu.py`; the only exclusions are ads/billing/QA strings).
- **Physics and timing**: all constants from `DECISIONS.md` (190 ms double tap, 700 ms catch, 100 ms running settle and
  ×0.82 reach, 2.2 s resolve, 24 s huddle, 12 Hz snapshots, gravity/run/bounce per arena, ball tuning, wind 0/0.45/1.5,
  Standard/Easy throw formulas, swipe→power mappings with points ≈ dp). The engine sub-steps at 1/120 s exactly as on
  Android.
- **House players**: the exact four-star table; catch roll `stars/5`, two stars lower while running; identical
  reaction, accuracy and power formulas; Kotlin `Random(seed)` replayed bit for bit, so a seeded local game makes the
  same bot choices.
- **Touch**: Android pointer semantics mapped to UIKit — first finger = `ACTION_DOWN`; the primary finger lifting while
  another stays down = `ACTION_POINTER_UP` (cancels); last finger up = `ACTION_UP`. `postDelayed` → main-queue work items.
- **Sounds and speech**: AVAudioPlayer pools (3 per sound, volume 0.7, `.ambient` session so the silent switch is
  honored); AVSpeechSynthesizer with the phone-language voice, US English for Hindi "STOP!" and for Hebrew Mia/Gaya before
  renaming (Android's rules). Android has no haptics, so none were added.
- **Screen**: kept awake like Android `FLAG_KEEP_SCREEN_ON`. Pages are portrait; a game uses the saved battle
  orientation (any orientation until ↻ is tapped, then portrait or landscape, remembered), and the result page keeps the
  game's orientation — Android's `requestedOrientation` rules, done with `requestGeometryUpdate` and an app delegate
  that reports the allowed orientations.
- **Firebase**: named app `minik-amudu-production` (Android's production app name), configured only from a bundled
  plist whose `BUNDLE_ID` matches and that has a `DATABASE_URL` (without one `Database.database(app:)` would throw).
  Anonymous auth, `.info/serverTimeOffset` clock, root `minikAmudu/rooms/{CODE}`.

## iOS-only differences

- Arena rendering is a UIKit/Core Graphics view. The Android code is immediate-mode Canvas drawing; Core Graphics is
  its direct equivalent and keeps text layout, radial lights and the `DST_OUT` night light pools identical. The drawing
  layer uses at most 2 pixels per point to keep 60 fps on older phones.
- Saved local game: UserDefaults `amudu.saved` holds JSON `{checkpoint, order}`. A Swift dictionary has no order, so
  the roster order is saved next to the Android checkpoint. Other settings use `amudu.*` keys with the Android names;
  the house-player choice is an ordered array.
- Snapshots from Firebase are decoded with actors in UTF-16 key order (Android uses its HashMap order, also arbitrary);
  lobby lines are sorted by slot so the list does not jump; online huddle proposals are listed in key order.
- Dialogs: Android AlertDialogs become SwiftUI alerts (pause, typed nickname, join code), confirmation dialogs (preset
  phrases, funny-word list) and an overlay card for the private nickname huddle (not dismissable, refreshed every
  350 ms). The pause alert cannot be dismissed by tapping outside; "Continue" is that path.
- No hardware back button: pages keep their Back buttons; in the arena the back chevron opens the pause dialog.
- Settings & feedback: "Rate the app" asks for the App Store rating prompt (Android opens its Play listing; the prompt
  never appears in TestFlight builds). "Share the game" and the feedback e-mail link to the game's public page
  `https://miniklearn.com/apps/amodu/` (Android links its Play listing; the App Store listing has no link yet).
- Help: Android passes `"…catch\\nDouble-tap…"` (a visible backslash and n, so no translation matches); iOS shows the
  line break the game screen uses for the same text.
- Practice aiming: Android maps a tap through the inverse of the projected 16 m square (`Matrix.setPolyToPoly`); iOS
  uses the camera's own inverse at the target's height, the same mapping.
- Touch times are the touches' own timestamps (Android `MotionEvent.eventTime`).
- Defensive differences where Kotlin would crash: unknown enum names fall back to defaults, a full room with no free
  slot is skipped, `coerceIn` with an empty range is clamped safely, NaN and out-of-range numbers convert like Kotlin
  `toInt()`. `Skills` clamps to 1…5 instead of throwing (only constants are used).

## Not ported (and why)

- AdMob interstitials, UMP consent, Play Billing "Remove ads", signed code redemption and the "Ads & purchases" page:
  iOS has no ads; it sells the full game instead ("Deliberate difference: iOS payment model"). The grown-up gate is
  ported (it guards Settings & feedback and the full-game purchase).
- The family module (`MinikFamilyServices`): "More Minik apps & games" is ported (2026-10-13) as a link in Advanced
  behind the grown-up gate (shared `Family/` module, `docs/family-messages-ios.md`). Its automatic promotions and
  Remove-ads reminders need ads and purchases, which stay off on iOS.
- `AdPolicyTest` (ad frequency policy): its code belongs to the excluded ads stack.
- Debug-only QA hooks (`qaDemo`, `qaCapture`, `qaOnline`, intent overrides, `qa-state.json`) and the Android debug
  build's Firebase emulator wiring: a fabricated `FirebaseOptions` app ID risks a FirebaseCore configuration exception;
  supply a real plist to test online play.
- Instrumentation tests that inject raw `MotionEvent`s or take screenshots: their logic checks are ported as unit tests
  (`DeviceEquivalentTests`); touch injection needs UI tests on a Mac.

## Tests

`Tests/AmuduTests` (XCTest, hosted in the app):

- `AmuduEngineTests` (16), `OctoberRefinementTests` (6), `RevisionTests` (21), `BrandingBallTests` (6),
  `NetworkStateTests` (4), `LanguageTests` (4): ports of every Android JVM test except `AdPolicyTest`, with the same
  seeds and tolerances.
- `KotlinParityTests`: XorWow reference values printed by kotlin-stdlib, `String.hashCode`, `floorMod`, name rules.
- `ProtocolTests`: member/config/command field names and enum wire names against the RTDB rules, JSON validity, saved
  game JSON round trip, Boolean/number separation.
- `DeviceEquivalentTests`: catch pose, back and mirrored frames, the huddle target's neutral pause, Hebrew feedback
  naming the other player, arena command routing, bundled art and audio, localized display names = Android `app_name`.
- `AmuduAppTests` (existing) kept.
- 2026-10-13: `SkyMenuTests` (sky palette and blend, reading-panel widths).
- 2026-10-12 additions: `GameRulesTests` (Android `GameRulesTest`), `RanksVoiceAndCourtTests` (`ProgressRanksTest`,
  `ConnectionRegressionTest`, `StopCallVoiceTest`, the rectangular-court case of `NetworkStateTest`),
  `SpudJourneyTests` (`SpudJourneyTest`, `JourneyLanguageTest`), `SpudReceptionZoomTests`, `WorldTests`
  (`ArenaCameraTest`, `LandscapeFramingTest`, `StableLabelsTest`, `PresentationLanguageTest`). The older ports follow
  Android's updated expectations (5 s players & scores view after a penalty, the honor penalty ending the throw, the 17
  config fields, the "Minik …" app names).

Firebase rules: `Tests/AmuduFirebase/rules-test.cjs` ran against the local database emulator jar only (no Firebase CLI,
no network): **106 passed, 0 failed, 0 production writes** (the same count as Android's 2026-10-04 run).

Static audit: `python Scripts/audit-amudu.py` (catalog identical, overrides identical, 0 Android literals missing,
assets present, Swift hygiene: one `@main`, LF endings, balanced brackets, no `try!`). `--hashes` prints the table
below.

## Least-sure compile spots

- `Amudu/Game/ArenaView.swift` — `MainActor.assumeIsolated` inside `DispatchWorkItem`/renderer closures (`afterDelay`,
  `canvas.renderer`); the `@objc` method on the `@MainActor` `DisplayLinkProxy`; callback properties typed
  `(@MainActor () -> Void)?`.
- `Amudu/Online/OnlineRoom.swift` — Firebase iOS signatures: `runTransactionBlock(_:andCompletionBlock:)`,
  `MutableData.childData(byAppendingPath:)`, `observe(_:with:withCancel:)` returning `UInt`, async `setValue`,
  `updateChildValues([AnyHashable: Any])`, `getData()`, `signInAnonymously()`; synchronous `setValue` calls are made only
  from synchronous contexts.
- `Amudu/UI/GameScreen.swift`, `Amudu/UI/Screens.swift` — SwiftUI alerts with `TextField`, the iOS 17
  `onChange(of:) { old, new in }` form, `confirmationDialog(titleVisibility:)`.
- `Amudu/Core/AmuduCodec.swift` — `CFGetTypeID(n) == CFBooleanGetTypeID()` on `NSNumber`.
- `Tests/AmuduTests/DeviceEquivalentTests.swift` — `@MainActor` test methods in a nonisolated `XCTestCase`.
- `Amudu/UI/SkySurface.swift`, `Amudu/UI/Widgets.swift` (2026-10-13) — `Canvas`/`GraphicsContext` drawing
  (`Path(roundedRect:cornerRadius:style:)`, `.linearGradient`), the `ScrollFinder` `UIViewRepresentable`, the
  `onPreferenceChange` + `MainActor.assumeIsolated` pattern, `.coordinateSpace(.named(_:))` with `frame(in: .named(_:))`.

## SHA-256 of the Android files used (for re-sync)

Android 372c448 (2026-11-19 sync). `app/build.gradle.kts` and `app/src/main/AndroidManifest.xml` are hashed at 372c448
(the owner has uncommitted edits there); every other file is the working tree, which equals 372c448.

| Android file | SHA-256 |
|---|---|
| `ASSET_MANIFEST.md` | `38704803848ea292215ae220f7c1c8442d489b8b8d09b1d89a97c91c51b54bed` |
| `BUILD_STATUS.md` | `60f810df8816244b43c32d03e2be3aa27047e7f2de33b10e3e925db002cf6ec8` |
| `DECISIONS.md` | `30c940a08e034a2a22344df42f50b6ba04499a0ee26784d5b3fde7bba13e335c` |
| `EXTERNAL_ACTIONS_REQUIRED.md` | `41145538429bfa515a4b521060eeaa3002c17ae72dcaf7e1ec549eca78c3dcfc` |
| `README.md` | `404f6709e955dc1279b94b9af8cb7be5c24ec2d534be8f29965db6a2d92301a4` |
| `app/build.gradle.kts` | `3d8d43a98f0fccd9f6ff4d052bfa741af01642034d499694948b07acd9fff2e2` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/AirborneCameraDeviceTest.kt` | `795df983aede2849ca447c21acc2f7c106b97f1a4ebb1d3bf19081e13ccfe0c5` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/AttackHeightDeviceTest.kt` | `64e2c4cc91c21e9c9b311c20491f6743039729c03ec035f84d1b279c928c1e9e` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/BalloonFollowupDeviceTest.kt` | `d809c73d17485467911e8749a3ed9312fdde8167f9c4ce7a6dc8984513fd7815` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/BlockedMovementDeviceTest.kt` | `8f551fc1dda3ef8af9e2b2c6823ac3a6f6e31d63d9830649c43742b55797704d` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/BotCallTurnDeviceTest.kt` | `4dbcfcad04030f05acb2d249a099f964d1b6df9e6d0e9e40676f9d3d1b82f5ad` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/BotHeightSamplingDeviceTest.kt` | `27dcf6970b92ad1d2255778165a7adf43f921deb0e5c9281c80a76dda207d949` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/CatchBurstDeviceTest.kt` | `827c7e7fff432adcf0e3a5eef0c0c87a3eab0aea25de6890c4695ef31f8f1110` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/CircleMotionDeviceTest.kt` | `8377a0a58ed76a4e36cd0c32476797a6a34d213da8e3483d780599069399f414` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/DeviceInteractionTest.kt` | `fc997f3de66b98ee350b1eca87a36bff96ac2d9e761eab790bcd6a1c5049dbe1` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/DropdownReviewDeviceTest.kt` | `2a178a50c173854083bf6034d05345596779ecb18888ff2217b83a61463dbbd2` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/EighteenIssueDeviceTest.kt` | `887ed0a56bd7020b3b626fb9e027db8d064d80547761b4db726bf96f49947189` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/EliminationDeviceTest.kt` | `49664abed2ad7e0663b4570cde2f53c1abbb71268494d082b2ae31c70fe05ff9` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/EnvironmentFeedbackDeviceTest.kt` | `c909ada88042ad61edf1eb2e65b196737db3376dba3a07ab23e55223e57b316f` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/ExtraAcceptanceDeviceTest.kt` | `fa3ac17a4336fa6f3c19fe9818c05e9ed945ba19342c72b43423419e38f446cb` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/FamilyLeagueDeviceTest.kt` | `9d1e30bce2a4d844b74e9d6222d077bfed6382984109b4aa65220d10723f38cc` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/FollowupDeviceTest.kt` | `d9fa8aa6a5d0db3d5ee1d0a56f9aeb6ba9b6d17403e34569fc634336e9060a0d` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/FollowupOnlineDeviceTest.kt` | `69137d1a6003bfce1dccdae67e84610aea4bc7bc7a67ae3725c6b62f8fdc2a08` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/GameRulesDeviceTest.kt` | `96c0a41366429b71c0e10d7b255394947ee23e180b30ef94bbfb9eae8ce8f969` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/IdentityDeviceTest.kt` | `06cde5b2915a5c862060904e253466bb3d1ab1ef831e001ee2dcadea4e2cba6c` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/LandscapeDeviceTest.kt` | `0bdfb8245cf841c5ba0cae48ee8f77173407a47edb460b592a03fe43c97a613a` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/LandscapeOnlineDeviceTest.kt` | `ea39c0d1eae139bcb54d959ed53f89ef7553e03775b73b88770e40ea8d3d20d7` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/LeagueCodeDeviceTest.kt` | `bf88dd065a50ce9df1363f69fc3ae6b3484e49f8ab5a0dbb4ddc12db13749b7a` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/LearningDeviceTest.kt` | `bce466971d49c59e4412c50ced18d51d8caa229593c526e3d4b0e4c540688467` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/LowTossSelectionDeviceTest.kt` | `3cc43785cf540da91b472c45edf77d5f0021625bc108da526e9217916fecb6b8` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/MonetizationDeviceTest.kt` | `68c7d35b9d7722931c8ab72f6d8a4115ca993d6d8178be0b570280657ba75b3a` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/NovemberFollowupDeviceTest.kt` | `e091c7c80aa929fcee72cdb6adf9e5de53c058f2c3b4d43993d0bd5422595375` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/NovemberThirtyIssueDeviceTest.kt` | `f8734a825adc682f7e99fb670262bdaef4fc03f580a8a47b56b22b9f750fe545` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/OwnerFeedbackDeviceTest.kt` | `072c90eb15f3c9d6e5d279d245c3174f78c388e6ad92437ccc92e837ff8f70ca` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/PresentationReviewDeviceTest.kt` | `8aa20b0e0b48144a6da99fbbff4c37aefb148e1e06652cda92757b6e060b0c7f` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/RefinementDeviceTest.kt` | `420ae7b1cd9ece0f6a91ab716f30214677e9ac6174dbc43ccb34130ba6837552` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/ReminderFollowupDeviceTest.kt` | `a8b90b77c29db01d7eba21939199653774e489e4690112528e478da6b24781ec` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/ReturnMovementDeviceTest.kt` | `7a223299a8330ecb35fb0fd13ea82937f12cb5edec89a2413adec65193c9d0f5` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/RoundVarietyDeviceTest.kt` | `afbe0dfc9b2e90a000f7ed6d93bd0ad66cb00d3a89fcc7c218d27b4624c68060` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/SetupFollowupDeviceTest.kt` | `6f5773811e7fa4556806c2e4b93b8a731140ef9d90240e004461b73d10cc0c15` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/SevenIssueDeviceTest.kt` | `f281700240b00d0ab2c2bcd525965972edf4e93c63c8b7e8cd8b6327d2614fbd` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/SpudJourneyDeviceTest.kt` | `40799d84c5d5d32ee246110a093d47ef6c5f567f5591077ae6393196a5bb69fc` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/SpudPackageDeviceTest.kt` | `454c888ecc0d89b3ce78e2e86f8fc632225593244e8e12c03e09c7d6a74b1116` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/SpudZoomDeviceTest.kt` | `8375b69edb1162011f01123925806a8747380a61e99be9c81c7d90f9befb51dc` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/StopCallAudioDeviceTest.kt` | `05131e71099e01c030c60c3e8b6093e35272b7650a6633c4b372bafd442e6352` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/StoreCaptureTest.kt` | `dca016874de65815d90bd6b68630275af932d64b341106413051976fbd95868e` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/StoreLearningDeviceTest.kt` | `ad819457cc76321005456981a38674beb0c7c43c9650fd377dd45c09d3d54907` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/StoreRefreshDeviceTest.kt` | `43e39d0c5ab8fbd9cb530c88325d125a133e7c1159c471748fd56ca403310975` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/SupplementalScreenReviewTest.kt` | `7456915929504c861487f48f166dacb4210e7de517913bd760a56b50bebf0fda` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/TargetBalloonDeviceTest.kt` | `16548beda91432a0ad3b8c2f4e4e7602d35d9f3e4425918baf732e3a894e45c9` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/VisualPolishDeviceTest.kt` | `d781b58fea631eb975519c9d9d8a58638e85a26ca2997950c57c63d3b27d063e` |
| `app/src/androidTest/java/com/appsbybros/minik/amudu/VisualRegressionDeviceTest.kt` | `0f69750447fbe5e1e952f9d4aa1692def64b0369bdecf1d525cf7ce3e6a6ac17` |
| `app/src/androidTest/java/com/appsbybros/minik/setupqa/FamilyMenuReviewDeviceTest.kt` | `c1f18ac45b922aa410710e4fb1cf7d6264c13efb9327e059597d7950374caee0` |
| `app/src/androidTest/java/com/appsbybros/minik/setupqa/MenuDiscoveryDeviceTest.kt` | `69601d825d2fae89fa594811de0996a7693d231dfb8ace2b82dfe3b0fd115d33` |
| `app/src/androidTest/java/com/appsbybros/minik/setupqa/MenuFormsDeviceTest.kt` | `1f8ba872322c8b4d741906882b2bc8b76243c4b4da2036258740f5e16c322e8c` |
| `app/src/androidTest/java/com/appsbybros/minik/setupqa/SkyMenuCaptureTest.kt` | `d89b521b51c93c416ab3fab0362e142668b23c2e42ac434ddd681406de9b72cb` |
| `app/src/main/AndroidManifest.xml` | `de7316517694a02d63f06fcbc16b91ffb3c8740ea4011eb9e701874a9f52ef05` |
| `app/src/main/assets/art/amber.webp` | `aafe40ef9fcef4cea3f79bd59782788bd82e70d7530c79848d37a09e1e72ab15` |
| `app/src/main/assets/art/amber_directions.webp` | `ee8d2aad1ba1c412c208bafa2ea2f222826604c2a5011ba5570f99d30d67bc81` |
| `app/src/main/assets/art/andromeda.webp` | `0a774402d7300cdb0da47b693702488f397edeb6a5c82c576a97f91eaa129b2b` |
| `app/src/main/assets/art/atlas.json` | `bbb612a0b3a1a2a79e73354d07c2cc705cb7b429e0ea7bb826f09bfc6d690240` |
| `app/src/main/assets/art/beach.webp` | `d31f1ab3d7f7e526ab8f5a4c3ad6bf25274ecc667958e6635b3dde790806d507` |
| `app/src/main/assets/art/beachball.webp` | `6c06be19bd1c2c84c102afe2dfdf328ab98420285d4cf813340599dd9a08cf54` |
| `app/src/main/assets/art/coach67.webp` | `739155051349f81539954c99fffd1a31d65d9d9d05ee3501c3c9005585e4eb51` |
| `app/src/main/assets/art/coach67_directions.webp` | `d3ab6747f0da9c786ee1bb43143ff54884af97938c179cebbb0dd57231b225fd` |
| `app/src/main/assets/art/comet.webp` | `06b716836ef6cb34eb25776a33aa21edd7cdcac6a839d0ee5ce87db9d124a288` |
| `app/src/main/assets/art/comet_directions.webp` | `8f6aa9717679aa596571aaf2aa98fb54506f450a2358d11dfad5c86375562446` |
| `app/src/main/assets/art/directions.json` | `619951eca803e265d17bddea61c889ac8849bda7424b14fc28af4d32c4f63c4b` |
| `app/src/main/assets/art/face-protection.json` | `b0d84ed161d88c82b4081b1e536fdc8716a8671262690c7f5a38298b2781146e` |
| `app/src/main/assets/art/flare.webp` | `61ecd11f421ada0316691f652a85d3fb5ac31551a55f86a7611d0def5542f22b` |
| `app/src/main/assets/art/flare_directions.webp` | `6c383f6797e4a8542bbb694a75a82aced02141ee2230fff1f8bcb614afe410c2` |
| `app/src/main/assets/art/foam.webp` | `8f7b30837bb7c8fd6e288ee0ef03ab9f4b484f3a6e10a7c77eb641c61d2968b3` |
| `app/src/main/assets/art/gaya.webp` | `bcd36629137fbc2ab233e476092a96508cbecb627dd82f3c8cfc9042d50f76a1` |
| `app/src/main/assets/art/gaya_directions.webp` | `c1f535b57fdecdb50ee9f10a00bf33970af28ef67331b4c344e59232a2be0178` |
| `app/src/main/assets/art/june.webp` | `f9c73ae55c447f8124aeb6844ba7307d3669e9fcadba0630e301296434102ffc` |
| `app/src/main/assets/art/june_directions.webp` | `bfc6b9495ccbb72e002b8e6931e9c5a540a54a44363c67fdde6bdfdf8678def5` |
| `app/src/main/assets/art/kyra.webp` | `0401549ca130dd45600d0d1aff3c2989c816fb2497a1bfb484325481122d2f69` |
| `app/src/main/assets/art/kyra_directions.webp` | `f6bd06204137ce02b7fdd872b50e0a5f4fef24743e2a6e7af04dbeab6815030f` |
| `app/src/main/assets/art/mia.webp` | `aa7cb8cc5dfbf0788999f4e7fe5d11b9a30acf52653b8e7f184bd962b9d386bc` |
| `app/src/main/assets/art/mia_directions.webp` | `9a967ef72c540d94d3f670b73e72b0a7cbfac46af8ad01c511562fb790b51ae2` |
| `app/src/main/assets/art/minik.webp` | `4ea4b9975bbdbba30240951c79ad38cbbdd6ab2f4bac9e27393dd11290f9eb63` |
| `app/src/main/assets/art/minik_directions.webp` | `e9845311ede62366289194018c709ea088f62e5b61451fe9b59b39fa5474bcdf` |
| `app/src/main/assets/art/miniko.webp` | `1803d53735b1dcaf7e900e02439528bc1a0388e54d7da964067c07d3dd81622a` |
| `app/src/main/assets/art/miniko_directions.webp` | `5289b05c9f632f9462b92f6e9963055b97a26abb39bcba2c1585f6d976713a47` |
| `app/src/main/assets/art/moshiko.webp` | `25c2644fc7e640e3b0797850ed310c70401b6ada519c8c57550c5f4ee458b6f2` |
| `app/src/main/assets/art/moshiko_directions.webp` | `affb1a276e1c002d91b7b6eb5f89fd1b2b49569e95a1e5b91f6f285a82e05691` |
| `app/src/main/assets/art/neon.webp` | `ddf50eac6667be189a34ab233b2b072e6571eef57b74af2b8aae75ceb1906582` |
| `app/src/main/assets/art/paint_balloon_menu.webp` | `6656063931ae7cc4635529a5be816810a36cccfc88269d5c19073b787dc1ffe8` |
| `app/src/main/assets/art/park.webp` | `312e65bacbeb5a7ad5387c40d71f4ede93fcb47889987bc1944d1fc74fb94259` |
| `app/src/main/assets/art/practice_tree.webp` | `4f97a6f4a1e93eb98da72b170b22ead31b30603b2bb3374d3a05416ff36fbbc5` |
| `app/src/main/assets/art/tennis.png` | `28dd6f6d70b7bec6d9af9524f7a76326689f9923dfb9900ada258d26fd257595` |
| `app/src/main/java/com/appsbybros/family/FamilyButtonAlignment.java` | `13f873c547787b7b02c4af821600c1d203bd32714a55278183a763159a544452` |
| `app/src/main/java/com/appsbybros/minik/amudu/AmuduActivity.kt` | `6d4135445c2f50f81ead1d0db63ba56a806b141b144169b0a5ea3278b44d2a04` |
| `app/src/main/java/com/appsbybros/minik/amudu/AmuduAds.kt` | `afe56a9340df226db05dbb83a4fb2b87217a8f31c9d2be3f8f88a16c9e9bef86` |
| `app/src/main/java/com/appsbybros/minik/amudu/AmuduView.kt` | `04c565a09c0bb8601f64dec8d987dda7f102278f0fe7714999c803a2defc2b32` |
| `app/src/main/java/com/appsbybros/minik/amudu/ArtStore.kt` | `74c76c275e02a9f727d0e5e1d015c69ac9d2838fb05b6e667e139fa2444454dc` |
| `app/src/main/java/com/appsbybros/minik/amudu/Codec.kt` | `12b6b40b2ffe0f309136aa5407b02461dc83d41a021eb4d2c8ecca2375c23ec4` |
| `app/src/main/java/com/appsbybros/minik/amudu/EnvironmentCopy.kt` | `36fa09bec8b2ae2b3c6a540d603696a98906e79bd82e42d213e0aef03c51b619` |
| `app/src/main/java/com/appsbybros/minik/amudu/FamilyLeague.kt` | `b8131b8fa79974fc38edce599d008662ff5e26d20fa8a3dec1eafdf5ac5547e1` |
| `app/src/main/java/com/appsbybros/minik/amudu/GameText.kt` | `9ca8eb2659cb01e03d22a55e213815390810f5d46d3cde1e957b7bd5b52128bd` |
| `app/src/main/java/com/appsbybros/minik/amudu/HebrewStopCalls.kt` | `b21fa8bd1aaec665799938f8f18b67499afd356fea6fc4932c056f0ed3f5ad99` |
| `app/src/main/java/com/appsbybros/minik/amudu/JourneyCelebration.kt` | `0a9fe3035e531afcd4171b5b5a8bea1d319ed68ae4a86ef1c3dfa48957295a1f` |
| `app/src/main/java/com/appsbybros/minik/amudu/LagDiagnostics.kt` | `9907d3edc09a2a66ba73585565e114b5076dd8e82bf3464c04209e7b9abb9b5f` |
| `app/src/main/java/com/appsbybros/minik/amudu/MotionState.kt` | `5204fdd417fa4870981bcf8e1cb33e99af42aa46137fc9075ee5ad6268f8fa61` |
| `app/src/main/java/com/appsbybros/minik/amudu/OnlineErrors.kt` | `4a1f5e597199fe364713a814f500dfc1bf6948e15283b3926f4b2e890e6988a7` |
| `app/src/main/java/com/appsbybros/minik/amudu/OnlineRoom.kt` | `f01916920b9f8cd70b18c19c85c09061f0a475327ba0ca764cb700b0f2cd95ed` |
| `app/src/main/java/com/appsbybros/minik/amudu/PaintEffects.kt` | `fff544162303eb90b2a49cc11496d97cecdd39e62ffd14071ab84376b4229553` |
| `app/src/main/java/com/appsbybros/minik/amudu/PictureChoices.kt` | `fd0dbcb7387a87a9436d4cabab32c81bca65a15d06c2b6737f9163020f5d9210` |
| `app/src/main/java/com/appsbybros/minik/amudu/ProjectileText.kt` | `badde206d11a4660db7626bc4255349aec56d8e6bf23e3569d674d6aa8f39745` |
| `app/src/main/java/com/appsbybros/minik/amudu/RuleText.kt` | `942a23a29c84dd9866a08fdd638e7c5431e222520e17188735aeb78fade65127` |
| `app/src/main/java/com/appsbybros/minik/amudu/SelectionWidgets.kt` | `00a90caf36c297959c909e79eb3118a9d7bc65b12d4c887eea8e4532a0cfe696` |
| `app/src/main/java/com/appsbybros/minik/amudu/SnapshotGuard.kt` | `d9ad8a39aaf31c92cc189186b3c1e33110248e2dc9aac8a1a82fe4e42447f507` |
| `app/src/main/java/com/appsbybros/minik/amudu/SnapshotPlayback.kt` | `9fb9ecd87748c509f1db8aa2758daa3a2c956c8dd6b86a8e26f1c113eecf364f` |
| `app/src/main/java/com/appsbybros/minik/amudu/SnapshotWire.kt` | `da887ffafffd5e99571e9be3f0665473173ba8865f2b9b79546002cbc37639f6` |
| `app/src/main/java/com/appsbybros/minik/amudu/SpudFollowupText.kt` | `6f25576e518f4fc9787ebdd72d4c4084c135ba7c01745c9ccdcb51fb8262ebdf` |
| `app/src/main/java/com/appsbybros/minik/amudu/StopCallVoice.kt` | `c0d977d008ef564c4c19fd3058bbc08810cffe844730da6958088dd9a90631ed` |
| `app/src/main/java/com/appsbybros/minik/amudu/core/ActorMovement.kt` | `7d62d81ff763afc0427c8aa86e3d61bba4d378c4dec3dee741fd7b720385af04` |
| `app/src/main/java/com/appsbybros/minik/amudu/core/AmuduEngine.kt` | `49e59e0414dcfcc6a904cb1f767929239d07a6ecebd60c02ad023c0d1cdadf96` |
| `app/src/main/java/com/appsbybros/minik/amudu/core/AttackPhysics.kt` | `160bdde50d759bd7366f41753d8d11e75148dca829928d4dd6ad5a5a83fce800` |
| `app/src/main/java/com/appsbybros/minik/amudu/core/BallContact.kt` | `cbf557c2e33f8bb77d27c410f0b0e99ff0267df9daeb354f325db1fc979f3c22` |
| `app/src/main/java/com/appsbybros/minik/amudu/core/BallShadow.kt` | `a50b6adb5120d63196e11103e7026b3ab1fb2413383ed3a12ad2bbcad0531e30` |
| `app/src/main/java/com/appsbybros/minik/amudu/core/CallLob.kt` | `6ee36af6d5d5c600fa3a78af14fda11940c9aa71beff2a66d7c6dd4b3aa69092` |
| `app/src/main/java/com/appsbybros/minik/amudu/core/CatchPhysics.kt` | `e76877abff3734111e0a41b15ac8d98925ed068d7a5f22ea38ea202a23ec91d5` |
| `app/src/main/java/com/appsbybros/minik/amudu/core/CircleFormation.kt` | `ca0449847f522fdbf5a893713509386b861b24085fe769dd64e9bce0611f0432` |
| `app/src/main/java/com/appsbybros/minik/amudu/core/EliminationExit.kt` | `107186f5776d757b2bd6dbda856558f07327c79abfcc0e5c42496e0ac770509d` |
| `app/src/main/java/com/appsbybros/minik/amudu/core/FleeMovement.kt` | `6c20376a0883f6215e147e3b92022f934ae97b7b0b52bd840fee3d4f164f5d95` |
| `app/src/main/java/com/appsbybros/minik/amudu/core/GroundBounce.kt` | `1288b942feebff43ef90a3781f12b405589a1563b0a4370fcf997ae50754afed` |
| `app/src/main/java/com/appsbybros/minik/amudu/core/Models.kt` | `a04ff2daae5ad3d77eb83ee7b22a82f2736e93c80b02b49321423a9e97515681` |
| `app/src/main/java/com/appsbybros/minik/amudu/core/PaintBalloon.kt` | `dd7c40ef9d32c0cefe96ff36e3c5c1e7d1963fc894283d3ce91f8d5b86be0ccb` |
| `app/src/main/java/com/appsbybros/minik/amudu/core/PracticeCurriculum.kt` | `5416afd15b0780c4e7f074b27bc572dec61cc34d5f396ffe0143a6b50a3265c2` |
| `app/src/main/java/com/appsbybros/minik/amudu/core/PracticeGuidance.kt` | `58c10ac53585cd3f63e86b21b144d09c623c4cd51782b5a4f0aa19c0861801bc` |
| `app/src/main/java/com/appsbybros/minik/amudu/core/ProgressRanks.kt` | `e8054e8f84eff8d46e2d6921735cddece135ba17d37e3222af10c8985ade04fa` |
| `app/src/main/java/com/appsbybros/minik/amudu/core/SpudJourney.kt` | `a7fbb04f604e6acfc037dcc232d845c2c172b958b079f8a16d70b63232afb891` |
| `app/src/main/java/com/appsbybros/minik/amudu/core/TargetThrow.kt` | `3bfdb1a10f04adfb2644f27c6874085a1bad26fba0450844e24711779fd89c24` |
| `app/src/main/java/com/appsbybros/minik/amudu/core/TossGesture.kt` | `8afa22c83b6a9c1d74e7cbece9d464b2c4a8e6b40e313c96fca0f073613076f6` |
| `app/src/main/java/com/appsbybros/minik/amudu/monetization/AccessCodes.java` | `e9443bc2daa05b4aac4944f4b869a20905e527ab095d4896f4cdbfba7c533eea` |
| `app/src/main/java/com/appsbybros/minik/amudu/monetization/AccessTokenRules.java` | `9047a310ba6d1b5316897716f362c99771cb120edb820f6cf257c0cac4c1e81e` |
| `app/src/main/java/com/appsbybros/minik/amudu/monetization/AdPolicy.java` | `8ea18feb67cec47efffcca5917400386ad8afa98d85377459a9489e820475d98` |
| `app/src/main/java/com/appsbybros/minik/amudu/monetization/CodesFirebase.java` | `64bda8afbc97e90db32b7736af3ab5f6006fa632261cc58788e218058b8f5908` |
| `app/src/main/java/com/appsbybros/minik/amudu/monetization/EntitlementStore.java` | `2766a7142796b0333b30fe101402c09609b941db495d980ef53a1aafec675964` |
| `app/src/main/java/com/appsbybros/minik/amudu/monetization/Entitlements.java` | `b51c3939041a2fae15ae1be6605767ea044bc7eaef042dade2eeb99676a2fefa` |
| `app/src/main/java/com/appsbybros/minik/amudu/monetization/LicenseReceipt.java` | `1e50da0e80bb945190af153bacde135387b63a7d85a1b3da15c8577573f7063c` |
| `app/src/main/java/com/appsbybros/minik/amudu/monetization/MonetizationConfig.java` | `957a966d210cf2fdbf43226ce62599a6a61925a16ef167a31efb67407eef85ca` |
| `app/src/main/java/com/appsbybros/minik/amudu/monetization/PlayPurchaseProcessor.java` | `d4fe78c96e5cde507f2d785dd6443cb219088518634c90e348f2eef8e9470979` |
| `app/src/main/java/com/appsbybros/minik/amudu/monetization/PurchaseOptionSelector.java` | `551ec9eacfabf7517209bd5fc6097fdc4c766b6a8f58a852d34e62fcd414dd03` |
| `app/src/main/java/com/appsbybros/minik/amudu/monetization/ReminderPolicy.java` | `f374228d881b5aefa25e885babe354a2fdb993b16ccaa43ce8c6da248093727d` |
| `app/src/main/java/com/appsbybros/minik/amudu/monetization/RemoveAdsBilling.java` | `af222b7d559057309545738516536e2b5d0ec99828e91026243a6dda4102c965` |
| `app/src/main/java/com/appsbybros/minik/localization/AppText.kt` | `bbdfbea52e7e3243a43ef3153fc005924c9f35a190beedd6f4f93802230be8d8` |
| `app/src/main/java/com/appsbybros/minik/localization/GameSupportText.kt` | `163c3c6d768383ebc310bc1a59dce57d75c1bee241488095c52330c52eaa1bef` |
| `app/src/main/java/com/appsbybros/minik/localization/LearningCopy.kt` | `71455bca53e2bd417b8e24ef8c1e14a9679cc858f8b8ddddf18a0f408f612afc` |
| `app/src/main/java/com/appsbybros/minik/localization/SpudEighteenIssueText.kt` | `58cce61e4e17d4d9370df0d4d426a00561dd3abb3105f54e76fed0d39a8a3298` |
| `app/src/main/java/com/appsbybros/minik/localization/SpudJourneyText.kt` | `be4697d8056ad4e462ccfad863bcb2c8a8af9f183a358125ffc0f47d93e9ebe8` |
| `app/src/main/java/com/appsbybros/minik/localization/SpudNovemberReviewText.kt` | `813d731eeb892818816db8dd540ac5e8ed0d0f6558790638a87c7fbe8b2e0d20` |
| `app/src/main/java/com/appsbybros/minik/localization/SpudNovemberText.kt` | `500212b9c1d3319a7d529a44d87e24a381f13d1bf90d3b3b3a42854a63e933d9` |
| `app/src/main/java/com/appsbybros/minik/localization/SpudTargetText.kt` | `6a810e8c229cdba8e50c7fd533e3e13dce0091e2836863c0e50e1757450350dc` |
| `app/src/main/java/com/appsbybros/minik/ui/CenteredToggleSpan.kt` | `cc417b7c358164293fe5e15dc0374522f54f59d6f05253f48438584507bd7306` |
| `app/src/main/java/com/appsbybros/minik/ui/GameDialogBuilder.kt` | `544dfc277cf50ac4f6036e2b4614d87c0d0861c9a32d22ee1f2b977076bd7e3e` |
| `app/src/main/java/com/appsbybros/minik/ui/SpudDialogStyle.kt` | `5a3d02929b1c39cc8b32fc7082b67e0cf7f4cedb374a319e7396ce32a4d3fccd` |
| `app/src/main/java/com/appsbybros/minik/ui/SpudPresentation.kt` | `03dcd8d760c5de44d0cbc46fc8887bb3836e7224ff6c75b6e0b6ef778b52c424` |
| `app/src/main/java/com/appsbybros/minik/ui/SpudSpinnerAlignment.kt` | `b66435c1f25d79fd90095c6550be09913c1253bb450cfea43dacfc65f899ad8a` |
| `app/src/main/java/com/appsbybros/minik/world/AirborneFraming.kt` | `c638aef7a1165e0f5e8bdb6b784c1cd1efaf18d6190c0730f7a4e1b819d017d9` |
| `app/src/main/java/com/appsbybros/minik/world/ArenaCamera.kt` | `99d43b98b016b67e60235ed6d2964b5551cbb193ea610d71b4bfa4499722e8a1` |
| `app/src/main/java/com/appsbybros/minik/world/ArenaWorldView.kt` | `2c9f4ba890c44aa25e292881e4ba362d0c48900d34b63497ff4d861cb825b809` |
| `app/src/main/java/com/appsbybros/minik/world/LandscapeFraming.kt` | `4c23f02f50af0036d12f1cbb482ea07080ff581ace1693846d9e6bd1cd6b6763` |
| `app/src/main/java/com/appsbybros/minik/world/SpriteSizing.kt` | `a8cd963751ecd9345f4bd8fea589bb0a2dc1e6c3ccb3932b01573a88f4e9a2bb` |
| `app/src/main/java/com/appsbybros/minik/world/SpudReceptionZoom.kt` | `6543b2c4733808bc483efcd76085d0197f3e96c7da82a03a4d0f19a42edd5282` |
| `app/src/main/java/com/appsbybros/minik/world/StableLabels.kt` | `5a5f18a39ca456780320998a60010bb8fc5ff2f740038023d20c050e3c73c597` |
| `app/src/main/java/com/appsbybros/minik/world/TightFraming.kt` | `6fe0432862987d48cd9fb0d2ccfd4cdf60ef91e1933b4e7e21e846c8febe6fc7` |
| `app/src/main/res/drawable-nodpi/amudu_icon.png` | `d511d8d1e96f82a84e808434427d9d54da098db15b098a4d4dfd425fe280c730` |
| `app/src/main/res/drawable-nodpi/launcher_ball.webp` | `ddf50eac6667be189a34ab233b2b072e6571eef57b74af2b8aae75ceb1906582` |
| `app/src/main/res/drawable-nodpi/minik_spud_launcher_glow.webp` | `8ec547f359e94636e8bef43e0982163a4b67907b0a30a49d6f055f47113df307` |
| `app/src/main/res/drawable/ic_dropdown.xml` | `05122469fcb5b5cdd9f3cb06f35ffd5ef281bfc53b9e069da13b61a80d0c12a2` |
| `app/src/main/res/drawable/launcher_foreground.xml` | `8133bacf5adf104c09592a874685c0c860dcb073486d0db60b12eeae8d40d7c2` |
| `app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` | `976f6ca1864caafdec22af1e8a968059c8549f7769133bc9da72906dda8c502f` |
| `app/src/main/res/raw/amodu_call_female.mp3` | `30bd4efbc94c929559c624fde1f9bec7615c4d24aae883583e7abb8806e3b713` |
| `app/src/main/res/raw/amodu_call_funny.mp3` | `ccccf17b6f922364708caae2f04165258c59866d84581ef6d2ee64f1390b02fc` |
| `app/src/main/res/raw/amodu_call_standard.mp3` | `679d3e5c2a62612702c86cb00e1ced8f4a3e2b26c42b8397bb066f9d5e429c10` |
| `app/src/main/res/raw/ball_catch.wav` | `bb6348a073afe0ddc0d7615df69938f8103777e4655b9bca875addf6d728dace` |
| `app/src/main/res/raw/balloon_burst.mp3` | `de20197edd7aec007b8a3d2e45e6add57163b6878c446e71501e4b51f531980e` |
| `app/src/main/res/raw/bounce.wav` | `046f176a0f68b1045ed831d4a039689791e9d55ba0e8ee8b1261f9042bdfcab3` |
| `app/src/main/res/raw/connected.mp3` | `7ef89d2e8bbc02e558b0bdbad3e0ae67b171ff8759e59a24bcd69ba0124f71e8` |
| `app/src/main/res/raw/player_ready.mp3` | `e36d07f178d49a49ebebdd56ae26dcfd0b9e5a5e4f45024d9eae8ffbe7e8c8e9` |
| `app/src/main/res/raw/sfx_finish.mp3` | `e5d4f4c8c99745d054493aeb5dc33ad30c0888777ccd327c9747c6ad45c406c1` |
| `app/src/main/res/raw/sfx_hit.mp3` | `de20197edd7aec007b8a3d2e45e6add57163b6878c446e71501e4b51f531980e` |
| `app/src/main/res/raw/sfx_pickup.mp3` | `e36d07f178d49a49ebebdd56ae26dcfd0b9e5a5e4f45024d9eae8ffbe7e8c8e9` |
| `app/src/main/res/raw/sfx_throw.mp3` | `3b5bf005e77004c80e785ad396a4d110f631dd35638117af6e356cfd9e1ad020` |
| `app/src/main/res/raw/sfx_wrong.mp3` | `c3af78f5f0a591aa006b0959aedaa8b20e0224bc7e1454857ac4784807cfd896` |
| `app/src/main/res/raw/whistle.wav` | `9d89cc81545aef6ef985f00f6acf1ad8a5e2ecb18e5e3f5f9cc24b0509c37929` |
| `app/src/main/res/values-ar/app_name.xml` | `9bc5c102c3ee0ab176fc74b7bc48d7cd30ec66d8a42b532a2c21325daa9c9f8e` |
| `app/src/main/res/values-es/app_name.xml` | `c41958128b828d9ce511ee8afb5b2906735d39d14be6f7764ed7a39ae88484e3` |
| `app/src/main/res/values-hi/app_name.xml` | `b2b1aa466eca6e80571aa8fa0d048d1cdffc22a0fd4235acdf5ef288ce83a1e1` |
| `app/src/main/res/values-iw/app_name.xml` | `2257a2d3cbd5aa4af2e5bc5cf0576a38616146f1ffcea9c9d03e719fd683f8ab` |
| `app/src/main/res/values-nl/app_name.xml` | `a5f9a0973b553d73bb99a74005818bee20a03bc2eedcc13dec69c1702ca5f54f` |
| `app/src/main/res/values-v27/styles.xml` | `b4e7495a06ecfb77eacdacef9cf89ebb9f2d1176d373d1b7cfd89823b779472c` |
| `app/src/main/res/values/app_name.xml` | `a5b8d8ec5cec93019f541fac34f6b6f9c67221aa194fc4a1f79ffdfdae00ce8c` |
| `app/src/main/res/values/dialogs.xml` | `6f80ae8ee5c788dec2dba9c84e6dfe42fcf9766ebfc27656a4ada8b34969e018` |
| `app/src/main/res/values/firebase.xml` | `83e81b6dbb90130fa2d30caf514ca809a2395710780c66737a9ad992eee1344a` |
| `app/src/main/res/values/launcher_colors.xml` | `b92e7f826723d5ebbbd88b70f4c414d716fbaa536312ef84dd0b18ea7a391546` |
| `app/src/main/res/values/styles.xml` | `4acc0e649e0bcc0fcbc9f5fed0b5b5cbd91ee56fb3e4987a757e99b8df919fd0` |
| `app/src/test/java/com/appsbybros/minik/amudu/AdPolicyTest.kt` | `363410165519f620e43b0b2681e09536383405ee9d97ed557ec5ad2131b93e0b` |
| `app/src/test/java/com/appsbybros/minik/amudu/AttackHeightTest.kt` | `e8cec8e6a117b8d8f44fdb519c5f7bee037e2c53e1e529246f50958afcd64117` |
| `app/src/test/java/com/appsbybros/minik/amudu/BalloonCadenceTest.kt` | `78cebc4c70ca6c714eb58ff5e8deacbecebf3ff1177035a37d6a6224bea55bd3` |
| `app/src/test/java/com/appsbybros/minik/amudu/BlockedMovementTest.kt` | `ccca9faf844b089d40fed72a76c666a937b676d317d3c95fb925bd5daef18e58` |
| `app/src/test/java/com/appsbybros/minik/amudu/BrandingBallTest.kt` | `623c9df9df93c141b41e3ab5784180e7697f83727750f3d10a3b834c9cb052d7` |
| `app/src/test/java/com/appsbybros/minik/amudu/CatchBurstRulesTest.kt` | `060a2ff5484b25254355d41fd19e5a1fe8f0f9d0e3737a9fb765408a680da5ae` |
| `app/src/test/java/com/appsbybros/minik/amudu/CircleMotionTest.kt` | `1a9d961752241c486ec671fc44c0eafc73dfb0490e148e900b237f569a129d31` |
| `app/src/test/java/com/appsbybros/minik/amudu/ConnectionRegressionTest.kt` | `447258053db209410f9a964efc96210fd98cde2db2382fa7f5592ac847edd3e9` |
| `app/src/test/java/com/appsbybros/minik/amudu/EighteenIssueRegressionTest.kt` | `6ce0e0ebbee71d20f0aacccef52d235bfa29871a2be6db914bae956241c27507` |
| `app/src/test/java/com/appsbybros/minik/amudu/EnvironmentFeedbackTest.kt` | `b71faf1e840785fc37c678b9d60e15b2389cb60782b39cbf47455fc717615c13` |
| `app/src/test/java/com/appsbybros/minik/amudu/FollowupPhysicsTest.kt` | `ac8b99c7fe723d82c3958a57c4e971eab3d76a284f5d4bd1787111f46939a32f` |
| `app/src/test/java/com/appsbybros/minik/amudu/LeagueStandingsTest.kt` | `c8e2713c946a903e9730052e16b5a3771efd21d6cf7de0bd571822c927c19e44` |
| `app/src/test/java/com/appsbybros/minik/amudu/MotionStateTest.kt` | `c60fb773f2c100e734acaaf114ca0a9a93f055ef0fcd9a185a7f13c47f324b68` |
| `app/src/test/java/com/appsbybros/minik/amudu/NetworkStateTest.kt` | `2350fc708853d5a25e4e591a7dda0ddf8c5114698a1b48673022487f6b738aff` |
| `app/src/test/java/com/appsbybros/minik/amudu/NovemberNetworkRegressionTest.kt` | `9457e49b3f8b6d782115474d3a9a501bc029ad978a94cf0a82fcbe3ca256c193` |
| `app/src/test/java/com/appsbybros/minik/amudu/RecallAndEliminationTest.kt` | `7ff68242c3d9b9367d34e0428d828c38269fa98a5a5ca58746c4b6a45e5c7842` |
| `app/src/test/java/com/appsbybros/minik/amudu/ReturnMovementTest.kt` | `d51be4444823f8624c59d93b6ab8a369c3c03b8b2df6fe39e2ccd9b32cb105f9` |
| `app/src/test/java/com/appsbybros/minik/amudu/RoundVarietyTest.kt` | `6f6913296c47a7b6dd904c58f9c0961cf51197daca4c57dc84ced72900a24774` |
| `app/src/test/java/com/appsbybros/minik/amudu/SnapshotWireTest.kt` | `0d635fff424ac469bb1a56ea9152d43f7b53e2cc34ca1ad9d9efe58d48333c8a` |
| `app/src/test/java/com/appsbybros/minik/amudu/StopCallVoiceTest.kt` | `2aaf1d817150018fc7882a1637f96e533a373c5d5b4664be392c413e1055afe0` |
| `app/src/test/java/com/appsbybros/minik/amudu/TargetBalloonTest.kt` | `d1d43ae3deedd8e5a6c5a8e29991de6fd166c6318ff427460529e4dc5bb876b4` |
| `app/src/test/java/com/appsbybros/minik/amudu/core/AmuduEngineTest.kt` | `44f5ce6c5ec90345ab9924ccfbcb5aa40a31e38331c748da0bd61b2e1647d0b2` |
| `app/src/test/java/com/appsbybros/minik/amudu/core/BotCallAndTurnTest.kt` | `a64401841eb26bb8603110322a726d68eb3d42419c2bf95e9a02e11aa5b4b62c` |
| `app/src/test/java/com/appsbybros/minik/amudu/core/GameRulesTest.kt` | `00dac4e635116246f4d7c7fb2ab4d3c5f51ecc7e45de4ed9e0bf0a7ac151925a` |
| `app/src/test/java/com/appsbybros/minik/amudu/core/JourneyLanguageTest.kt` | `464e1915a8fd210572b91694361ebea15488fe1ad8f7df678500fe42873729e1` |
| `app/src/test/java/com/appsbybros/minik/amudu/core/LearningCurriculumTest.kt` | `cbeb25a201bda393ec5b6f31a6386589c6e284644c2be8598c227bdd5629cfeb` |
| `app/src/test/java/com/appsbybros/minik/amudu/core/OctoberRefinementTest.kt` | `a4f171ef40af57f7c3c215b93bb7717c8f611454802752c80e0cfbb683bb1b80` |
| `app/src/test/java/com/appsbybros/minik/amudu/core/OwnerFeedbackPhysicsTest.kt` | `5eb1a4615d69ca477efeeb2326ef7e14852d3408f92ab2562fe32d3c844873b5` |
| `app/src/test/java/com/appsbybros/minik/amudu/core/ProgressRanksTest.kt` | `0d2c1da8485be6fc83f2fdb3cdf41807a7cd7d811f6b8a35fa3de2f360af5e73` |
| `app/src/test/java/com/appsbybros/minik/amudu/core/RevisionTest.kt` | `ebfb75a4b13f52b346b4e38dcb70d61d2f0ab6854b2dd3054787e6301238fbaf` |
| `app/src/test/java/com/appsbybros/minik/amudu/core/SpaceTossTest.kt` | `f132ea0083612e7f73c0d6b7ab3633a02d390010205d2d32cb68ecc3d3e292b0` |
| `app/src/test/java/com/appsbybros/minik/amudu/core/SpudJourneyTest.kt` | `a5b4fa2af0cf286c952766a6dc04154bd34174bb267decaf9e23f5e9543b51b9` |
| `app/src/test/java/com/appsbybros/minik/amudu/monetization/AccessTokenRulesTest.java` | `43b8293af8dfdfd0422a5554fc0c1a05476c9af100575f0b07326621047e8c48` |
| `app/src/test/java/com/appsbybros/minik/amudu/monetization/EntitlementStoreTest.java` | `12f74f7dad1c179e0c7ea48c99cf0aa1193443768db47c627f61820633d71ed6` |
| `app/src/test/java/com/appsbybros/minik/amudu/monetization/PlayOwnershipStoreTest.java` | `bef8953f4e4d4a4e0b445e186ea002ace70013bae3f9095bb6933e0d959d8b75` |
| `app/src/test/java/com/appsbybros/minik/amudu/monetization/PlayPurchaseProcessorTest.java` | `1763fbbe3b6125602e8fb84ffa79d8e3c15f913f3a2e09ae0e3c0f7167010291` |
| `app/src/test/java/com/appsbybros/minik/amudu/monetization/PurchaseOptionSelectorTest.java` | `528de85e7d0604491d3d70ce48ae305d87e938e14bd026271bf15e0f95a154bb` |
| `app/src/test/java/com/appsbybros/minik/localization/LanguageTest.kt` | `5117994247324664c1255499754de48c2b5c9fe40e2505c62f3656c0d53c8cb0` |
| `app/src/test/java/com/appsbybros/minik/localization/PresentationLanguageTest.kt` | `72f24ec485e3b6b25d0e85d39e8a34b44302eb166245ce5721c47357ae030079` |
| `app/src/test/java/com/appsbybros/minik/world/AirborneFramingTest.kt` | `b75cd331e37ab0aed3beef45571446f12082919133a0829f3d672d667bb7e2d4` |
| `app/src/test/java/com/appsbybros/minik/world/ArenaCameraTest.kt` | `5bb0693d72c6a64f36aa0221ac305b91d26854b582a812fce10eeb6a479bc404` |
| `app/src/test/java/com/appsbybros/minik/world/LandscapeFramingTest.kt` | `e1adb5112cc0d974a7617f984c070ec220cb1b00f566a265f4addf184ad632f9` |
| `app/src/test/java/com/appsbybros/minik/world/SpudReceptionZoomTest.kt` | `68323b15bced282267486974d441d11125b2a2b34119c44c219a7d97079183e7` |
| `app/src/test/java/com/appsbybros/minik/world/StableLabelsTest.kt` | `0c62659dbedfd8f7c9f11c330455781f76a4cba91fd78f9411212d0e03d6cb32` |
| `firebase/database.rules.json` | `c80298ba1bb68ffffcb7262cca727883bb5fb87dd52895079c06d25e542abf7f` |
| `firebase/firebase.json` | `8980a41bdbd7e364174987800b571acfefb536320293a4bc2fdae3d7c1510e75` |
| `firebase/rules-test.cjs` | `867ebd57d4ee444a84d56b764d7861ead885b74483135b5a334e86aae0e7553d` |
| `firebase/start-emulators.ps1` | `28c3a00402243f93613c6d97a5eded2a27cb62ea3d243678bbc607c34c5d71f2` |
