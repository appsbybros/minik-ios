# Minik Splash — iOS port handoff

## Re-sync of 2026-10-12

Brought up to the current Android app: `C:\Projects\MinikSplash` at a9fc598 plus its uncommitted
daily paint journey work (`PaintChallenges.kt`, `SplashDrills.kt`, `JourneyCelebration.kt`, the new
text files and the edits to `SplashActivity`, `SplashView`, `OnlineSession`, `WorldCodec` and
`core/*`). The first port was taken from 92f49b4; this pass covers everything since (branch
`port/spud-splash`, continuing the WIP of `wip/spud-splash-port`, commit 6b3a954).

What changed on iOS:
- Core: 20 x 20 arenas; difficulty (Easy / Standard / Pro speed, thinking time and room); house
  players' star ratings acting on real play; play feel (acceleration, braking, running, Standard
  lift, Hard swipe power); the wider answer ring; wall battles ("Paint walls · teams", hit effects:
  paint only, 3 hits and an 8-second rest, or a slowdown per hit); the 30-step daily paint journey
  (paint walls, pattern, letter, shape, targets, races, passing, and the duck / jump / sidestep and
  ring / ground drills); lobby rules (`LobbyPlan`, `RoomInputPolicy`).
- Arena: drill and paint-wall cameras, the whole-field close-up, perspective paint walls with the
  graffiti cornice and target rings, drill rings, cues and counters, landing rings for passes, the
  journey and wall-battle HUD and advice, "Throw balloon" on the camera button in Hard throwing, the
  reachable aiming grip, Android's rotating tips, and taps that paint a wall or aim through a ring.
- Menus (SwiftUI): the home sections of Android `FamilyMenu.organize` (Start & learn with the avatar
  picker, Play, Advanced, and the Parent zone link), the Play menu (continue a battle, cup or room;
  arena, players, single battle or a 3- or 5-battle cup, difficulty, paint walls, create or join a
  room, house players only), house-player cards with stars, the paint-wall options, the daily
  journey page and its result (with the celebration), the join page, colour ranks, the grown-ups
  page (rate, share, feedback, game sounds) behind the parent gate, game orientation, and results
  with the wall-battle note and the cup length.
- Online rooms: house players chosen by the host (`meta/housePlayers`), removing a player, a
  transactional start (`starting`) that re-checks the roster, `rosterCount`, the room difficulty in
  `meta/config`, committed results applied on every device, input that stops at the first sign of
  the end, 16-digit command ids, a removed player returning home, and Android's generic
  "Could not connect. Please try again." messages.
- Battles start once the loading screen has faded (Android `battleReady`); battles rotate (setting
  and ↻) while pages stay portrait.
- Texts: the catalog follows Android's composition (1001 rows from `AppText.kt`,
  `GameSupportText.kt`, `SplashFeedbackText.kt` and `SplashJourneyText.kt`).
- App icon: Android's launcher (off-white / blue split with the burst balloon) at 1024 px.
- Privacy manifest: `SystemBootTime` (35F9.1) for `systemUptime`, which the game clocks read.
- Firebase rule copies in `Tests/SplashFirebase/` refreshed (Android changed them since 92f49b4).
- Tests: every Android unit test except `MonetizationTest` (104 of 106), plus the iOS golden and
  parity tests; the `engine` and `translations` golden vectors were regenerated from the current
  Android classes.

Nothing was compiled on this machine (no `swiftc`): everything was written and checked by reading,
tree-sitter parsing and `Scripts/audit-splash.py`.

Android source: `C:\Projects\MinikSplash` (read-only; versionCode 3, a9fc598 plus uncommitted work,
106 JVM tests). iOS target: `MinikSplash` in `project.yml` (bundle `com.appsbybros.minik.splash`),
sources under `Splash/`, tests under `Tests/SplashTests/` (scheme `MinikSplash`, test target
`SplashTests`).

## What was ported

| Area | Status |
| --- | --- |
| Simulation (`SplashEngine`): movement, explicit pickup, walk-to (Easy), aim, throw, jump, crouch, personal space, collision geometry, paint layers, cleaning, shield, wrong-answer pop, house players with star skills, difficulty, play feel, FFA/teams scoring, wall battles and hit effects, the daily journey (`PaintSession`, `SplashDrillSession`), results | Ported statement by statement, same constants and random-number order |
| Questions: generators, per-skill learning, unlock rules, 24 English + 12 world facts | Ported; facts generated from `Learning.kt`; Kotlin `Random` reproduced bit-exactly |
| Gestures: 220 ms single/double tap, slop, locked targets for two independent fingers, cancel | Ported (`Gestures.swift`); UIKit touches mapped to Android pointer ids |
| Arena renderer (`SplashView.kt`): camera (follow, focus, player view, orbit, drill and wall framing), GPU ground (`ArenaWorldView`), balloons with private answers, actors with direction and locomotion atlases, painted variants, stable name tags, aiming arc and grip, shots, splashes, particles, paint walls, drill rings, whole-field close-up, HUD, advice, tutorial overlay, pause overlay | Ported to Core Graphics and Metal (`SplashArenaView.swift`, `Splash/World/`) with the same geometry in points |
| "Learn with Minik" (11 steps: Easy/Standard walking and throwing, mistakes, jump, duck, free practice), settings saved from the tutorial | Ported |
| Menus: home sections with the avatar picker, Play menu, paint-wall options, house players (star cards), daily journey and its result, join page, lobby (remove, house players, start checks), settings (difficulty, controls, format, arena, court, balloons, game orientation, subjects with tap and drag), colour ranks, grown-ups page, parent zone (multiplication gate), progress, results (FFA rows, team panels, wall note, cup lines) | Ported to SwiftUI |
| Pause (Continue / Return to menu), saved battle, 3- or 5-battle local cup surviving relaunch, colour-rank receipts, journey progress (schema 2), lifecycle save | Ported |
| Texts: English, Hebrew, Spanish, Arabic, Hindi, Dutch; device-language rule; RTL | Ported: the full 1001-row Android catalog in `apptext.json` with the same lookup and template logic |
| Sounds (hit, throw, wrong, finish, pickup at 0.35), menu music loop (0.20), question read-aloud | Ported (AVAudioPlayer / AVSpeechSynthesizer) |
| Haptics | Android has none, so none on iOS |
| Online rooms (RTDB protocol, leases, handover, house players, removal, checked start, commands, snapshots, checkpoints, committed results, cups) | Ported (`OnlineSession.swift` + `FirebaseSplashDatabase.swift`); active only when `GoogleService-Info.plist` is bundled |
| Orientation: portrait pages, battles by the "Game orientation" setting, ↻ | Ported (`SplashOrientation.swift`, `project.yml`) |
| Launcher icon | Rendered from Android's adaptive layers (`AppIcon.png`, 1024 px) |
| Ads, billing, code redemption, UMP | Not ported (by request); the "Ads & purchases" button is hidden |
| Android unit tests | 104 of 106 ported (the 2 `MonetizationTest` cases test left-out code), plus golden parity tests |
| Firebase rules and rules test | Reference copies in `Tests/SplashFirebase/` (byte-identical) |

## Android → iOS file map

| Android | iOS |
| --- | --- |
| `core/SplashEngine.kt` | `Splash/Core/SplashEngine.swift` (`Actor` is `SplashActor`) |
| `core/SplashConfig.kt` | `Splash/Core/SplashConfig.swift` (`Character` is `SplashCharacter`) |
| `core/PlayerSettings.kt` | `Splash/Core/PlayerSettings.swift` |
| `core/Learning.kt` | `Splash/Core/Learning.swift`, `Splash/Core/QuestionFacts.swift` (generated) |
| `core/Gestures.kt` | `Splash/Core/Gestures.swift` |
| `core/Facing.kt` | `Splash/Core/SplashConfig.swift` (`Facing`) |
| `core/PaintChallenges.kt` | `Splash/Core/PaintChallenges.swift` |
| `core/SplashDrills.kt` | `Splash/Core/SplashDrills.swift` |
| `core/PlayFeel.kt` (with `SplashRanks`) | `Splash/Core/PlayFeel.swift` |
| `core/GroundBalloons.kt` | `Splash/Core/GroundBalloons.swift` |
| `core/LobbyPlan.kt`, `core/RoomInputPolicy.kt` | `Splash/Core/LobbyPlan.swift` |
| `world/ArenaCamera.kt`, `StableLabels.kt`, `SpriteSizing.kt`, `ArenaWorldView.kt` | `Splash/World/*.swift` (the ground renders with Metal) |
| Kotlin `Random`, `String.hashCode`, `HashMap` order, stable sorts | `Splash/Core/KotlinCompat.swift` |
| `localization/AppText.kt`, `GameSupportText.kt`, `SplashFeedbackText.kt`, `SplashJourneyText.kt` | `Splash/Localization/AppText.swift` + `apptext.json` |
| `SplashView.kt` | `Splash/Game/SplashArenaView.swift`, `Splash/Game/SplashPalette.swift`, `Splash/Game/PlanarMap.swift` (Android `Matrix.setPolyToPoly`) |
| `BattleLoadingView.kt` | `Splash/Game/BattleLoadingView.swift` |
| `ArtStore.kt` | `Splash/Game/ArtStore.swift` (`SplashPose` holds the pure pose logic) |
| `MenuMusic.kt`; SoundPool and TTS in `SplashActivity.kt` | `Splash/Game/SplashAudio.swift` |
| `SplashActivity.kt` | `Splash/App/SplashController.swift`, `Splash/App/SplashViews.swift`, `Splash/SplashApp.swift`, `Splash/App/SplashOrientation.swift` (`requestedOrientation`) |
| `JourneyCelebration.kt`, `SelectionWidgets.kt` (`SkillStars`, `AvatarArrow`), `ui/GameDialogBuilder.kt`, family `FamilyMenu` | `Splash/App/SplashViews.swift` (`JourneyCelebration`, `SkillStars`, `AvatarArrow`, `PauseDialog`, `MenuSection`, `SectionButton`, `FamilyLink`) |
| `LocalBattleStore.kt`, SharedPreferences | `Splash/App/SplashStore.swift` |
| `WorldCodec.kt` (with the `Node` helpers) | `Splash/Net/WorldCodec.swift`, `Splash/Net/Node.swift` |
| `ReplicaEvents.kt`, `ReplicaTimeline.kt` | `Splash/Net/ReplicaEvents.swift`, `Splash/Net/ReplicaTimeline.swift` |
| `OnlineSession.kt` | `Splash/Net/OnlineSession.swift`, `Splash/Net/SplashDatabase.swift`, `Splash/Net/FirebaseSplashDatabase.swift` |
| `SplashAds.kt`, `monetization/*.java` | not ported |
| `assets/art/*.webp`, `res/drawable-nodpi/splash_icon.png` | `Splash/Assets.xcassets/Art/*.imageset` (lossless PNG, pixel-identical) |
| `assets/art/atlas.json`, `directions.json` | `Splash/Art/` (byte-identical) |
| `res/raw/*.mp3` (the six used files) | `Splash/Audio/` (byte-identical) |
| `test/.../SplashCoreTest.kt` | `Tests/SplashTests/SplashCoreTests.swift` |
| `test/.../LearningAcceptanceTest.kt` | `Tests/SplashTests/LearningAcceptanceTests.swift` |
| `test/.../RevisionTest.kt` | `Tests/SplashTests/RevisionTests.swift` |
| `test/.../NetworkStateTest.kt` | `Tests/SplashTests/NetworkStateTests.swift` |
| `test/.../ReplicaEventsTest.kt`, `ReplicaTimelineTest.kt` | `Tests/SplashTests/ReplicaTests.swift` |
| `test/.../LanguageTest.kt` | `Tests/SplashTests/LanguageTests.swift` |
| `test/.../HouseSkillsTest.kt`, `KnowledgeTest.kt`, `PresentationFeelTest.kt`, `RoomInputPolicyTest.kt`, `RosterArrivalTest.kt`, `world/ArenaCameraTest.kt`, `world/StableLabelsTest.kt`, `localization/PresentationLanguageTest.kt` | `Tests/SplashTests/PlayFeelTests.swift` |
| `test/.../SplashJourneyTest.kt`, `PaintFeedbackTest.kt`, `JourneyLanguageTest.kt` | `Tests/SplashTests/JourneyTests.swift` |
| (golden vectors from the Android classes) | `Tests/SplashTests/AndroidGoldenData.swift`, `KotlinCompatTests.swift`, `EngineParityTests.swift` |
| `firebase/database.rules.json`, `firebase.json`, `rules-test.cjs`, `start-emulators.ps1` | `Tests/SplashFirebase/` (copies) |

## Decisions

- **Exact randomness.** `KotlinRandom` is a bit-exact XorWow (`kotlin.random.Random(seed)`),
  including `nextBits(0)` consuming a value and the rejection loop of `nextInt(from, until)`.
  Questions, option order, balloon colours and layouts and house-player choices therefore match
  Android for the same seed and question secret, so an iOS authority, an Android authority, a
  checkpoint restored on the other platform and saved battles all agree. Golden vectors, captured
  by running the actual Android classes (`app/build/tmp/kotlin-classes/debug` with kotlin-stdlib
  2.2.21) through a scratch Java harness, pin this in `AndroidGoldenData.swift`.
- **Java ordering.** Android iterates Firebase maps as `java.util.HashMap`; the lobby list and the
  host's team assignment follow that order. `JavaOrder.hashMapOrder` reproduces it (checked against
  real `HashMap` output). Cup standings use `String.hashCode() xor seed` exactly. Kotlin's stable
  `sortedBy` is reproduced with `stableSorted`.
- **Renderer.** Android draws immediate-mode Canvas. The closest exact port is a UIKit view drawing
  with Core Graphics (`draw(_:)` with `drawsAsynchronously`), driven by a `CADisplayLink` capped at
  60 Hz, with the static arena pre-rendered into a separate image layer (Android's cached
  `arenaBitmap`). SpriteKit was not used because it would have meant re-modelling every draw call
  and text layout. dp and sp become points one to one. The menus are SwiftUI.
- **Catalog.** The complete Android catalog (820 rows, shared by the Minik games) is stored
  verbatim and in order as JSON rather than Swift literals (type-checker safety). Lookup, `{n}`
  templates (longest key first, stable), padding preservation and the " · " prefix rule are
  identical. Hebrew always comes from the call site, as on Android.
- **Robustness instead of crashes.** Android `require`s that could only fail on corrupt saved or
  network data (roster size, enum names, question validity) return or ignore on iOS instead of
  terminating; normal behaviour is unchanged. Outgoing JSON and Firebase payloads are sanitised
  against NaN and infinity (which the engine never produces).
- **Firebase.** The protocol sits behind a small `SplashDatabase` protocol so the app compiles and
  runs fully offline. A `FirebaseApp` is configured only when `GoogleService-Info.plist` is in the
  bundle. Every build then uses that registration (named app `minik-splash-production`, database
  URL from the plist, paths `minikSplash/rooms/...`), as Android now does. Only an explicit debug
  launch with `-qaOnline YES` (Android's `qaOnline` extra) uses the local emulator (`127.0.0.1`,
  Auth 9099, RTDB 9005, project and namespace `demo-minik-splash`), with `-qaDuration` for the
  battle length. Without the plist, "Create room" and "Join room" show Android's message "Online
  play is not available yet. You can play with house players."
- **Perspective walls.** Android draws each paint wall through a four-point `Matrix` (a perspective
  map) and inverts it for taps. Core Graphics only concatenates affine transforms, so `PlanarMap`
  (the same projective map) transforms every wall point: cells and the border are mapped
  quadrilaterals (exact), ovals and curves are sampled outlines, strokes are bands between two
  mapped outlines, and the cornice gradient runs between its mapped end points (a close linear
  approximation of Android's perspective gradient).
- **Catalog order.** Kotlin `+` keeps a key at its first position and takes the last value; the
  audit composes the rows in the order of Android's `rows` expression across the four text files.
- **Golden vectors.** `engine` and `translations` were regenerated by compiling copies of the
  current Android `core` and `localization` sources in a scratch folder (kotlin-compiler-embeddable
  2.2.21 from the Gradle cache; nothing was written in the Android project) and running a harness
  that prints the same rows as the original one. The other vectors did not change (`Learning.kt`
  and the Kotlin runtime are unchanged). Unlike the first port, the regenerated engine rows were not
  replayed through a Python mirror of the Swift engine; the XCTest suite checks them.
- **Orientation.** Android asks for portrait on every page and, in battle, FULL_SENSOR, PORTRAIT or
  SENSOR_LANDSCAPE from the setting, and ↻ switches between portrait and landscape. iOS does the
  same with `supportedInterfaceOrientationsFor` and `requestGeometryUpdate`; `project.yml` now lists
  the landscape orientations.
- **Battle start.** As on Android, the arena starts stopped and runs once its first ground frame has
  replaced the loading screen and the app is in the foreground.
- **App icon.** Android's adaptive launcher, visible 72 dp window: the radial #B5ACFF / #7E95FB /
  #3E77F3 background under the #F1F3F4 fade, and the foreground balloon re-rendered from
  `art/directions/balloon-burst-logo-source.png` (1254 px) at the foreground's placement (264/432 at
  83, 81), so the 1024 px icon stays sharp. Compared with a Pixel 6 launcher capture: mean
  difference 4/255.
- **Support links.** Android shares its Play listing; iOS shares and mails
  `https://miniklearn.com/apps/minik-splash/` (as Spud uses its own page), and "Rate the app" asks
  StoreKit for the rating prompt (TestFlight never shows it).
- **Audio session.** Sound effects use the `ambient` category. While the menu loop plays the app
  switches to `soloAmbient`, and it deactivates with `notifyOthersOnDeactivation` when the loop
  stops, mirroring Android's audio-focus gain and abandon around the menu music.

## iOS-only differences

- No system Back button: the in-game "❮" (pause) and the page "Back" buttons cover every Android
  Back path; "main-menu Back exits" has no iOS equivalent.
- Lifecycle: scene phase `inactive`/`background` is Android `onPause`, `active` is `onResume` (same
  saving, music, sound and network handling).
- Toasts are a small overlay. The pause dialog is a light card like `GameDialogBuilder` (tapping
  outside continues, as cancelling does on Android); the parent gate, share and feedback dialogs are
  SwiftUI alerts with a text field.
- The timer digits are always Latin (`m:ss`); Android `String.format` could localise digits.
- The home sections remember open or closed per title in UserDefaults
  (`family_menu_sections.<title>`), like Android's `family_menu_sections` preferences.
- Fonts are the system font at Android's sp sizes (Android uses Roboto) and do not follow
  Dynamic Type.
- Saved data uses UserDefaults keys named after the Android preference files (`minik_splash.*`,
  `splash_local_battle.battle`, `splash_online.room`) with the same JSON values.
- No `.lproj` / `InfoPlist.strings`: Android does not localise the app name ("Minik Splash").

## Not ported (and why)

- `SplashAds.kt`, `monetization/*` (AdMob, UMP, Play Billing, signed code receipts) and the
  "Ads & purchases" page: ads, purchases and code redemption stay off on iOS for now. The parent
  zone keeps Android's text "Learning and purchases, in one place." unchanged (consider rewording
  once iOS purchases exist). `MonetizationTest` (2 tests) therefore has no port.
- The family-services module (`com.appsbybros.family`): "More Minik apps & games" is ported (2026-10-13) as a link
  in Advanced behind the parent gate (shared `Family/` module, `docs/family-messages-ios.md`); its promotions
  and reminders need ads, which stay off on iOS. The Android menu labels without a Splash button ("Public rooms &
  championships", "Saved games") and two arena names of another game ("Parking plaza", "Five-floor
  tower") are the remaining Android-only texts, with "Share" (Android's chooser title).
- DEBUG-only QA hooks (`qa*` intent extras, `qa-state.json`, visual-capture preferences): Android
  test tooling, not product behaviour; only `qaOnline` / `qaDuration` exist, as debug launch
  arguments.
- `androidTest` device tests (real touch, typography and language captures): they drive the
  Android view hierarchy; their behavioural assertions are covered by the ported unit tests. iOS
  UI tests can be added once the app has run on a simulator.
- Unused Android files: the untinted `splash_0..5.webp` (intermediate exports ArtStore never
  loads), the legacy `sfx_throw.mp3`, and `ui/CenteredToggleSpan.kt` (not used by Splash).
- The Firebase rules test was not run: it needs the Firebase emulator and CLI, which could not be
  guaranteed to stay fully offline here. Android's run (65 checks, local emulator only) is
  recorded in `BUILD_STATUS.md`. To run it locally: `Tests/SplashFirebase/start-emulators.ps1`,
  then `node Tests/SplashFirebase/rules-test.cjs` (both still point at the Android machine's
  dependency paths).

## Activating online play later

1. Register the iOS app `com.appsbybros.minik.splash` in the approved Firebase project and add its
   `GoogleService-Info.plist` to `Splash/` (the repository ignores such files by default; add an
   exception like the other apps if it should be committed).
2. Deploy the reviewed `minikSplash` rules (`Tests/SplashFirebase/database.rules.json`) through the
   owner's workflow. No rules were deployed by this port.
3. Every build then creates and joins rooms; only a debug launch with `-qaOnline YES` uses the
   local emulator.

## Checks run here

- `python Scripts/audit-splash.py` (2026-10-12): catalog identical (1001 rows, Android's composition
  order); facts identical (24 + 12); every English/Hebrew text passed to `tr()` / `AppText.t()` on iOS
  exists verbatim in the Android sources (221 pairs, 0 unmatched; the 20 Android-only pairs are ads,
  purchases and codes, the family-module labels, two arena names of another game and the chooser
  title "Share"); 86 images pixel-identical (art and pro-world ground textures); 6 MP3 and 2 JSON
  files byte-identical; 47 Swift files LF-only with exactly one `@main`.
- Tree-sitter parse of every Splash source and test file: clean apart from the grammar's known
  `x as? T ?? y` limitation in three unchanged lines (valid Swift).
- Golden vectors from the real Android classes: 6 Kotlin `Random` streams, 8 `hashCode`s, 4
  `HashMap` orders, 168 generated questions, 6 skill-choice sequences (from the first port), and
  116 catalog lookups in four languages and 54 engine question layouts (regenerated 2026-10-12 from
  the current sources, see Decisions).
- App icon render compared with a Pixel 6 launcher capture (mean difference 4/255).
- The whole repository audit suite: 38 pass; the 6 failures (`audit-firebase-leaderboard`,
  `audit-minik-visual-assets`, `audit-modern-pong`, `audit-multi-pong`, `audit-release-closure`,
  `audit-remote-records`) fail identically on a clean export of the previous commit.
- Not run: Swift compilation and XCTest (no macOS here).

## Android files read (SHA-256)

| File | SHA-256 |
| --- | --- |
| `ASSET_MANIFEST.md` | `4b29f2ac2769fcec372b8404487a18ee17f3528e4b233fe67b57a0b241d16a5e` |
| `BUILD_STATUS.md` | `e020d36e534a0ee348b48b487e3e5d9a095e3815edd9f55af990b1a135aa121e` |
| `DECISIONS.md` | `b1d31ad304c1d395322047d42a6925c40db2a8f2b8782fcedc91093d3c37ac85` |
| `EXTERNAL_ACTIONS_REQUIRED.md` | `4fb3e94a132ce9a88e6a024cb99712e625e8b84caff66d1c95e684e6e9107ad2` |
| `NEXT_GAME_BRIEF.md` | `83aad9be1aa26eb97a9c10ab6188086e2b8ea73e99004065743a9163deb95c4d` |
| `README.md` | `07a9ee298cdc99b39b5bcc3e37b53dd794bb4cce8420841cd2c0294b9b8a05a3` |
| `app/build.gradle.kts` | `46bddaa81da7175d772c8d1876ce28c100c7d3c51fcfecc247ba57afbd5653e9` |
| `app/src/androidTest/java/com/appsbybros/minik/splash/CupAndRanksDeviceTest.kt` | `15118105bd5ae4e84a9eadafd114444ebe702a28c3d24a68f1e1351f39535288` |
| `app/src/androidTest/java/com/appsbybros/minik/splash/DeviceInteractionTest.kt` | `9a0574fb0038b8e6db09c20a335c6172d973beb3797dde1b62bd731ef6ae5c47` |
| `app/src/androidTest/java/com/appsbybros/minik/splash/FeedbackDeviceTest.kt` | `6a10d5bcfe865a0e90dbf5bd9162a37b12149d7045016744e195ac2a8c530d42` |
| `app/src/androidTest/java/com/appsbybros/minik/splash/JourneyDeviceTest.kt` | `8e017f4b52b72e9d144812fc078ecc4f70e54175cc0aa6b4981787371a3d0887` |
| `app/src/androidTest/java/com/appsbybros/minik/splash/LanguageDeviceTest.kt` | `60fa707c84076d00f2f2395aea6ec245d02746cd9e5f451e86d51610aaed4f56` |
| `app/src/androidTest/java/com/appsbybros/minik/splash/LiveActivationDeviceTest.kt` | `eb59bfa83da20f4bbb651ffa84875fafc756c4d79d296c55771439461a2edffb` |
| `app/src/androidTest/java/com/appsbybros/minik/splash/MenuRevisionDeviceTest.kt` | `7495340f445fd81f1faaab936fbf08b61509ddb623a4f4d432d184d12f9bfdb9` |
| `app/src/androidTest/java/com/appsbybros/minik/splash/OnlineDeviceTest.kt` | `60fd610ce9fcf61896a488865c706252ae75e08aef9035288fd96583c86ed43b` |
| `app/src/androidTest/java/com/appsbybros/minik/splash/PresentationDeviceTest.kt` | `beebcd8d295cf5566b797f7f191e1088267ab85a2753ad723df9a45e0d6e84f0` |
| `app/src/androidTest/java/com/appsbybros/minik/splash/StoreCaptureTest.kt` | `55c38f6232e00e2fb9bed109dcbfba2932026d20d9a954b8f2af4512014359db` |
| `app/src/androidTest/java/com/appsbybros/minik/splash/TypographyCaptureTest.kt` | `63172872429925c0bfe1da2e3f294cc15a8847c026c77d9a772ad70d3a8277f3` |
| `app/src/androidTest/java/com/appsbybros/minik/splash/VisualRegressionDeviceTest.kt` | `99bacf01fc3b3f5e71e1399e5f8894356bd7de3714961dc151daedd0bdbbf34d` |
| `app/src/main/AndroidManifest.xml` | `80399c9ee6b5d9ff954e82aaa054a907ffe7b8013b7bf2da1abdfcc84a5f45c4` |
| `app/src/main/assets/art/amber.webp` | `aafe40ef9fcef4cea3f79bd59782788bd82e70d7530c79848d37a09e1e72ab15` |
| `app/src/main/assets/art/amber_directions.webp` | `ee8d2aad1ba1c412c208bafa2ea2f222826604c2a5011ba5570f99d30d67bc81` |
| `app/src/main/assets/art/amber_locomotion.webp` | `77a650be7d3e98bd757e59d1eeb0e85580c0db1e3dcb4a6826cda931716a56bd` |
| `app/src/main/assets/art/arena_andromeda.webp` | `0a774402d7300cdb0da47b693702488f397edeb6a5c82c576a97f91eaa129b2b` |
| `app/src/main/assets/art/arena_beach.webp` | `d31f1ab3d7f7e526ab8f5a4c3ad6bf25274ecc667958e6635b3dde790806d507` |
| `app/src/main/assets/art/arena_park.webp` | `312e65bacbeb5a7ad5387c40d71f4ede93fcb47889987bc1944d1fc74fb94259` |
| `app/src/main/assets/art/atlas.json` | `84278dde8c760396f4a0d910339fdad3b264794f614ae824f180537bd2785faf` |
| `app/src/main/assets/art/balloon_blue.webp` | `5e5714d323e2e54d6555f575b6523e40d4232cebe5f9401a7e13b641c71c913c` |
| `app/src/main/assets/art/balloon_cyan.webp` | `09e357f0aa6e08516e73add8fe05f9bdef63d577c2230d944224ba4a631d61fc` |
| `app/src/main/assets/art/balloon_green.webp` | `a9b7c59db424495aaf77a470f2ab7330ce6aaa777d04358ca8389875428dd96a` |
| `app/src/main/assets/art/balloon_orange.webp` | `46dcbf9ba96ee4470901eb7028e967fc560fd533ab0fcda88fbbdb51c1331a4d` |
| `app/src/main/assets/art/balloon_pink.webp` | `1000f991dbc32d1cf830d12f259c3e1b0416b4cf0acbfc2264c2cada17ee03af` |
| `app/src/main/assets/art/balloon_yellow.webp` | `01f7d28f388d448b58d063b72ef9ec4d06fea74fd0c732fc65a582ed0cf43fc7` |
| `app/src/main/assets/art/coach67.webp` | `739155051349f81539954c99fffd1a31d65d9d9d05ee3501c3c9005585e4eb51` |
| `app/src/main/assets/art/coach67_directions.webp` | `d3ab6747f0da9c786ee1bb43143ff54884af97938c179cebbb0dd57231b225fd` |
| `app/src/main/assets/art/coach67_locomotion.webp` | `6ed279b84f811e44c902aad95428ca7c1324343170f6393d2103d59cc58b9fed` |
| `app/src/main/assets/art/comet.webp` | `06b716836ef6cb34eb25776a33aa21edd7cdcac6a839d0ee5ce87db9d124a288` |
| `app/src/main/assets/art/comet_directions.webp` | `8f6aa9717679aa596571aaf2aa98fb54506f450a2358d11dfad5c86375562446` |
| `app/src/main/assets/art/comet_locomotion.webp` | `eb423fd1a9cc01376b0bc3b65f0de1d6d2bb53223114000ae25877f52556981c` |
| `app/src/main/assets/art/directions.json` | `3f919d2a6605ee93ad5390900f417bba0496402c6290407376dc9bb20f567ad3` |
| `app/src/main/assets/art/flare.webp` | `61ecd11f421ada0316691f652a85d3fb5ac31551a55f86a7611d0def5542f22b` |
| `app/src/main/assets/art/flare_directions.webp` | `6c383f6797e4a8542bbb694a75a82aced02141ee2230fff1f8bcb614afe410c2` |
| `app/src/main/assets/art/flare_locomotion.webp` | `dfce6873b1da7411ec2f4c3fc87efc76d2778e42d90299ef77ccee0565361a11` |
| `app/src/main/assets/art/gaya.webp` | `bcd36629137fbc2ab233e476092a96508cbecb627dd82f3c8cfc9042d50f76a1` |
| `app/src/main/assets/art/gaya_directions.webp` | `c1f535b57fdecdb50ee9f10a00bf33970af28ef67331b4c344e59232a2be0178` |
| `app/src/main/assets/art/gaya_locomotion.webp` | `8aa0a1538be7182272b98e94f31c5fa239c6325a5540d3de23a622cdaba9d316` |
| `app/src/main/assets/art/june.webp` | `f9c73ae55c447f8124aeb6844ba7307d3669e9fcadba0630e301296434102ffc` |
| `app/src/main/assets/art/june_directions.webp` | `bfc6b9495ccbb72e002b8e6931e9c5a540a54a44363c67fdde6bdfdf8678def5` |
| `app/src/main/assets/art/june_locomotion.webp` | `50a1fc81dad2716dc369658c40b81bdc2bd56aa71a802516eb848fe8de07996c` |
| `app/src/main/assets/art/kyra.webp` | `0401549ca130dd45600d0d1aff3c2989c816fb2497a1bfb484325481122d2f69` |
| `app/src/main/assets/art/kyra_directions.webp` | `f6bd06204137ce02b7fdd872b50e0a5f4fef24743e2a6e7af04dbeab6815030f` |
| `app/src/main/assets/art/kyra_locomotion.webp` | `c5a1ca6e6fd02eba1c4aec99dbbc2e830181eda382505e49d6b0f887348bd08c` |
| `app/src/main/assets/art/lagoon.webp` | `baf843f999ba83a672493ca68bed2da2d2bc9aefc731359b59233f2487e7a839` |
| `app/src/main/assets/art/mia.webp` | `aa7cb8cc5dfbf0788999f4e7fe5d11b9a30acf52653b8e7f184bd962b9d386bc` |
| `app/src/main/assets/art/mia_directions.webp` | `9a967ef72c540d94d3f670b73e72b0a7cbfac46af8ad01c511562fb790b51ae2` |
| `app/src/main/assets/art/mia_locomotion.webp` | `ac57b9e26371185c3553aa7d0c6f6a5e4e75cc25c2736d64ceea71b96c28b59c` |
| `app/src/main/assets/art/minik.webp` | `4ea4b9975bbdbba30240951c79ad38cbbdd6ab2f4bac9e27393dd11290f9eb63` |
| `app/src/main/assets/art/minik_directions.webp` | `e9845311ede62366289194018c709ea088f62e5b61451fe9b59b39fa5474bcdf` |
| `app/src/main/assets/art/minik_locomotion.webp` | `f55710df6dcb2709dead3cf9617fe3789fb4fb2ccaa539826601ab46c7910013` |
| `app/src/main/assets/art/miniko.webp` | `1803d53735b1dcaf7e900e02439528bc1a0388e54d7da964067c07d3dd81622a` |
| `app/src/main/assets/art/miniko_directions.webp` | `5289b05c9f632f9462b92f6e9963055b97a26abb39bcba2c1585f6d976713a47` |
| `app/src/main/assets/art/miniko_locomotion.webp` | `d0c0ba47648ad02bdadadd4622d4a8597789324dcd6cf6558bba30b2ad6c3f9d` |
| `app/src/main/assets/art/moshiko.webp` | `25c2644fc7e640e3b0797850ed310c70401b6ada519c8c57550c5f4ee458b6f2` |
| `app/src/main/assets/art/moshiko_directions.webp` | `affb1a276e1c002d91b7b6eb5f89fd1b2b49569e95a1e5b91f6f285a82e05691` |
| `app/src/main/assets/art/moshiko_locomotion.webp` | `ada06a4c51b54d759344da3ce4961af4f6d090a78890b8043e040fd110eef586` |
| `app/src/main/assets/art/splash_0.webp` | `208a81fbc46464e8c7e7085d20c445f59bcfa4be9f5b0bfaa30222da5b4bc30c` |
| `app/src/main/assets/art/splash_0_c0.webp` | `f398926fc7593c1e3ce06fad0dabfda555cf32393a4c3d5d22b4464d95f37ac0` |
| `app/src/main/assets/art/splash_0_c1.webp` | `147ae66b0fb7d3b6d2738fe4da77898b3cb2f68aab5a2fb6e89ff03127774535` |
| `app/src/main/assets/art/splash_0_c2.webp` | `e8d7b055790fcbe9eb54477cbc229ff37cfb027c3eac6d8f227f45e0511fb16c` |
| `app/src/main/assets/art/splash_0_c3.webp` | `29171f681a501318c260eae634317b29af7276557a1c8a8656e0eb180c8c0436` |
| `app/src/main/assets/art/splash_0_c4.webp` | `67777d7ca54389a6d080e18687fd732d7df886d7a54d5fe5fda47088249c2100` |
| `app/src/main/assets/art/splash_0_c5.webp` | `5568781d2278dd6fa4e70a431586c0f7572343367389bebc60324f0e555f5c71` |
| `app/src/main/assets/art/splash_1.webp` | `55d0d041d7dba8b27572b6dfcb135ca64c96d79d30fc1681e10a60f5c51657db` |
| `app/src/main/assets/art/splash_1_c0.webp` | `6b5e2aafc54eee8bd106ef76a7c98dc250d7b55cfd41f0a601c65d8f1a9d91f2` |
| `app/src/main/assets/art/splash_1_c1.webp` | `8aa03297bc24605484dec54240559fd7edf2c947423bc1ef0dd70f8981c539d1` |
| `app/src/main/assets/art/splash_1_c2.webp` | `fe5dc2fe17713d656c676ca1643b555c755f2bb1137916c086c7751ce250df34` |
| `app/src/main/assets/art/splash_1_c3.webp` | `8cc2631f37166fb143dffbf7045d2f7a718fd2bf6c3b79e4e7c555e52dbc1e3f` |
| `app/src/main/assets/art/splash_1_c4.webp` | `05b706345d7694b520685063ebd30bbd2a9a815fcf75c393e1cd7369b37fbdfa` |
| `app/src/main/assets/art/splash_1_c5.webp` | `52080b0a7db37bcebc78e8b0de225bef88f8af8a6f04cbe0d10e4dcdd62d78c2` |
| `app/src/main/assets/art/splash_2.webp` | `d00b1d78db7451debb8c5185d63125f4ade27de806bc4808425756829d29775d` |
| `app/src/main/assets/art/splash_2_c0.webp` | `7fa005e4b65b82c5c665159f52ac63531d16e6575d7aa84b91d75a4122587348` |
| `app/src/main/assets/art/splash_2_c1.webp` | `01da5bab20eace4ff8837f18577b425f21b10e5d845e9a2463067d346f61ff3e` |
| `app/src/main/assets/art/splash_2_c2.webp` | `5e8f4aef577d42739987c0293295bf325f5f60e5137e085a7435c325d3ac5c57` |
| `app/src/main/assets/art/splash_2_c3.webp` | `2437af6f1bec85b7851ddaac1b9200ebec971ecf17889260e7db2e34a2e6a2ad` |
| `app/src/main/assets/art/splash_2_c4.webp` | `4e168cb0dce34d79160a9cc7bc1ddb28747fb8d103d4bcd8fa0c5f732c43a7b4` |
| `app/src/main/assets/art/splash_2_c5.webp` | `47505f015526bcee573f3b61049e88bab2dbb06992c2e4bfb285a1d99b61653a` |
| `app/src/main/assets/art/splash_3.webp` | `8e1d9989fbae2f67efa15fbcae8165e95144bbda2992ac10f6e20f29ff1649a2` |
| `app/src/main/assets/art/splash_3_c0.webp` | `c2743d640bd3fa84153c1ea72abb2ea9122fe3a761cdaa8e22465271a80012ef` |
| `app/src/main/assets/art/splash_3_c1.webp` | `7fc9b0586d7eb5e4a797099f11415f892a5d62f4e1c73e7a297e0fccbd9f9c88` |
| `app/src/main/assets/art/splash_3_c2.webp` | `71d10316e8b14a9f9d015bb0633eb937acdaa7e576183ecb0c7c3987e1af1378` |
| `app/src/main/assets/art/splash_3_c3.webp` | `1fc5731173b0aa39fa6ef8aa7e7e8dad1be75d52b783c51d1d2f67d9dc47a0fe` |
| `app/src/main/assets/art/splash_3_c4.webp` | `2e071d70bc59b4e30ffe5071e0bbcef07ce59d62a11da1a9701c2e4fbfbe3933` |
| `app/src/main/assets/art/splash_3_c5.webp` | `355e016a80c601f474111d599927b26a028842b19b3b7a73d7d5d793eef370f3` |
| `app/src/main/assets/art/splash_4.webp` | `45987e2c098850103e8c3d662d621eb8ce566af8c92779e62c9c49aa34145dc8` |
| `app/src/main/assets/art/splash_4_c0.webp` | `1f21a0a7273e296d7f9792414e1278541a53072703cba328e814c2ef8b3fe5f2` |
| `app/src/main/assets/art/splash_4_c1.webp` | `91f6a59e0e07a4768d578997ef3c1f22dafca378c49bd22580f32959d0457f4b` |
| `app/src/main/assets/art/splash_4_c2.webp` | `913b51bb321f7ca06dfa120d354769062d95e6f94f94afd89789a4f8b46211e5` |
| `app/src/main/assets/art/splash_4_c3.webp` | `67f7ede367b055b1a2c4afb2e285439376e3f7d9a94924a05bda566db7426075` |
| `app/src/main/assets/art/splash_4_c4.webp` | `6e859729792075ebcf8a27029fc9cad7c32ffe21c829a645ff4cd28585e261cb` |
| `app/src/main/assets/art/splash_4_c5.webp` | `0b6a3fdd57b40a31cf4674c97e62de8cd956dbe74ee6c4f089b83f460032ba81` |
| `app/src/main/assets/art/splash_5.webp` | `2103a6c1c2a89657d9be5b27f12bc430e0ab2e86fc44a288fe6b5a4fb7a11b10` |
| `app/src/main/assets/art/splash_5_c0.webp` | `9bba6126946e4216120336325155e813d5715c3fb03be01df457664f6cc22a0a` |
| `app/src/main/assets/art/splash_5_c1.webp` | `1c5556f0e2e01f29d5722b937e76ff980c3e1b608715ad9011c8a0505fa2b5aa` |
| `app/src/main/assets/art/splash_5_c2.webp` | `645c867a4374657099a4d2f8ff4850bc5f479f565b768a2a45b0d55f52c29060` |
| `app/src/main/assets/art/splash_5_c3.webp` | `75cfa50b2ca1d0fb9ef87b6d4c9b9892d922b3c6d8e9c54b602efafc6b7bd186` |
| `app/src/main/assets/art/splash_5_c4.webp` | `bb0fb61308acdd58eccf4ce2fc36dd1619e285c22940919e15e2cee3f5a475b6` |
| `app/src/main/assets/art/splash_5_c5.webp` | `805e1e59e524eff1d270bfb152a85bedbaf3030d003f903c8d74ba571e4378cb` |
| `app/src/main/java/com/appsbybros/minik/localization/AppText.kt` | `211e512e1fe15d5a73f73588b350a7d587ce2b911775a66c87f389d48d30134e` |
| `app/src/main/java/com/appsbybros/minik/localization/GameSupportText.kt` | `974101bfa25ffc966f1139b762770f505bd3c2bcc43b62317fcd9851893af1d8` |
| `app/src/main/java/com/appsbybros/minik/localization/SplashFeedbackText.kt` | `f8ff666fc06a7d64197011520102d4dab3b42ee07a109509b572c59ae2e1db44` |
| `app/src/main/java/com/appsbybros/minik/localization/SplashJourneyText.kt` | `17bdfaa732a531f11f08bfe27993012d9014bc63984955c8f1ef85ff3d0bb694` |
| `app/src/main/java/com/appsbybros/minik/splash/ArtStore.kt` | `3cd418262ade96568ee010c6e847a2604aa9313c11b636fe06c9463fdb962e06` |
| `app/src/main/java/com/appsbybros/minik/splash/BattleLoadingView.kt` | `fdf62bd6d9bedcfaddfe485cf4ba63933556f4be6d3d89633dad15e7ec2446ac` |
| `app/src/main/java/com/appsbybros/minik/splash/JourneyCelebration.kt` | `945a79f64983f04ca7091f30216bbdad3dc019e86a46000a7d9249df4c65d578` |
| `app/src/main/java/com/appsbybros/minik/splash/LocalBattleStore.kt` | `2996c06e2801ad67c69695fa600d4eca64b3fc7443aa27a5b755c44ef086beee` |
| `app/src/main/java/com/appsbybros/minik/splash/MenuMusic.kt` | `337f60ec6aa501d7d4d150348972a920999f6d1a70d454359c66cfe43fedc55f` |
| `app/src/main/java/com/appsbybros/minik/splash/OnlineSession.kt` | `c28fba623542c33b24bcdc20c6c8415554ef26f6dd5fc51b222e65132b98ed89` |
| `app/src/main/java/com/appsbybros/minik/splash/ReplicaEvents.kt` | `34afbaf8992f72aa67d98000d6190c2c6615e1c5a6aafdf62c61d948b4aaf129` |
| `app/src/main/java/com/appsbybros/minik/splash/ReplicaTimeline.kt` | `268b5779cd608b48fe5dd116c79cc51c5a33585e5bfa57a4902235eeba60a39f` |
| `app/src/main/java/com/appsbybros/minik/splash/SelectionWidgets.kt` | `099c9238d38c79f69f65fdf043a18256cf454217c87b35ce47a0321bee4304c3` |
| `app/src/main/java/com/appsbybros/minik/splash/SplashActivity.kt` | `264a67e9ac2897133256ae4d9f5f30735244688384557e7027eed54f71c2aeda` |
| `app/src/main/java/com/appsbybros/minik/splash/SplashAds.kt` | `d1f0f8a7e4ed71d7083bf12449062bf4f4149cd1e506b187f28ec22e8b3a573e` |
| `app/src/main/java/com/appsbybros/minik/splash/SplashView.kt` | `9ea500933d6781b422406f1bb1beb8c8a7ccc85eeae88b0a799d2ef16cceb7d0` |
| `app/src/main/java/com/appsbybros/minik/splash/WorldCodec.kt` | `6cba39deb45f57fff791665bdea4c90a50c3b95665496edc8a3f002a35926ffa` |
| `app/src/main/java/com/appsbybros/minik/splash/core/Facing.kt` | `50949c3f6420ae9f3cefbce0ae080ddd94f96608757ede510cf8936ae844458d` |
| `app/src/main/java/com/appsbybros/minik/splash/core/Gestures.kt` | `4e630cf7a31008050b5f2e1f19cec52902c7d91916734f73e5f82ea1f1d883ae` |
| `app/src/main/java/com/appsbybros/minik/splash/core/GroundBalloons.kt` | `f55108952e15983438df405dd97e11ccb4d99bb2e8b5feb26ac3984ccbb6cd62` |
| `app/src/main/java/com/appsbybros/minik/splash/core/Learning.kt` | `92150dbfdd36d2a7e8f045b1fa117138847b412381d9ce6e5e9e3f263688e07f` |
| `app/src/main/java/com/appsbybros/minik/splash/core/LobbyPlan.kt` | `2ce5a2599dac97cc86f8e056030eebdc444d200094b5d0fc1983f3182600afe3` |
| `app/src/main/java/com/appsbybros/minik/splash/core/PaintChallenges.kt` | `fadf626c21b090b563fa0a62a9215255a916df6e27e834381f2f84eb2c272038` |
| `app/src/main/java/com/appsbybros/minik/splash/core/PlayFeel.kt` | `56d7d9a82a59cd871f86820b3e10d5d74dfaceb796be95fb624047c3036d7dd3` |
| `app/src/main/java/com/appsbybros/minik/splash/core/PlayerSettings.kt` | `56cdae96e4903742381a4966c71a6b2fa28a72289343767a1a84f596db89ef16` |
| `app/src/main/java/com/appsbybros/minik/splash/core/RoomInputPolicy.kt` | `42c469cc3f14e0a221c6b75bcbcff790674414df5097ec469bf15527b1fd1e12` |
| `app/src/main/java/com/appsbybros/minik/splash/core/SplashConfig.kt` | `1333429cb18fd082a723ebda1b3feca9b4fd7194c389fae72a1b0615c46fbc9a` |
| `app/src/main/java/com/appsbybros/minik/splash/core/SplashDrills.kt` | `ff6e84f02de015543c36c971cbc0c0fd4949179d6e5da0825ca0c8f71df19b3b` |
| `app/src/main/java/com/appsbybros/minik/splash/core/SplashEngine.kt` | `a248efa1d14ad219f26fdf339603b4aebae2e2c6845ee5f499027c02e89b1395` |
| `app/src/main/java/com/appsbybros/minik/splash/monetization/AdPolicy.java` | `532b4f2c874a968e65847c86871e8d8f83b4e1c63a939a34d95bb1ad39325189` |
| `app/src/main/java/com/appsbybros/minik/splash/monetization/Entitlements.java` | `f98ffb71eb39c76a5fd1cbee3085687fdf56c7319bc7bfb7fb5d68c0a64a02e0` |
| `app/src/main/java/com/appsbybros/minik/splash/monetization/LicenseReceipt.java` | `c2aefe4d1e6451cbaec7c36468bc7814f4bd0033109be4dc8873ec39483f5379` |
| `app/src/main/java/com/appsbybros/minik/splash/monetization/MonetizationConfig.java` | `03ba5e6aa163ade0b26926cb0b9cff12384de14a89a0beec7e95a9c809a836ea` |
| `app/src/main/java/com/appsbybros/minik/splash/monetization/RemoveAdsBilling.java` | `e2b5ae94b78d1d3a1928865bbe997dad78d1108bf1e37029e48cfcc4664de4d6` |
| `app/src/main/java/com/appsbybros/minik/ui/CenteredToggleSpan.kt` | `cc417b7c358164293fe5e15dc0374522f54f59d6f05253f48438584507bd7306` |
| `app/src/main/java/com/appsbybros/minik/ui/GameDialogBuilder.kt` | `687b4ad92ae83247a4e8face51bcb8ee4527f480cc6a59e1efb52719d15d3536` |
| `app/src/main/java/com/appsbybros/minik/world/ArenaCamera.kt` | `ca6227e0d8aae45127851b2d0f7c60d7c00e1d69a07e79feaf357e8553c61ea8` |
| `app/src/main/java/com/appsbybros/minik/world/ArenaWorldView.kt` | `ece7d350dc7440f31681734b4927d1e95ead98d5fca0c85f75e7eeb49dcf3fe6` |
| `app/src/main/java/com/appsbybros/minik/world/SpriteSizing.kt` | `a8cd963751ecd9345f4bd8fea589bb0a2dc1e6c3ccb3932b01573a88f4e9a2bb` |
| `app/src/main/java/com/appsbybros/minik/world/StableLabels.kt` | `5a5f18a39ca456780320998a60010bb8fc5ff2f740038023d20c050e3c73c597` |
| `app/src/main/res/drawable-nodpi/splash_icon.png` | `3b01da18d243e51253912f60a0ea51d41b1e024e67dd3afe063a8afd893a3d93` |
| `app/src/main/res/drawable-nodpi/splash_launcher_foreground.png` | `7bbb2be5f27f969c6db80fd3d539b1d5303d891ccfdf34a662bdb42441f39642` |
| `app/src/main/res/drawable/launcher_clock_blue_background.xml` | `e3cc55b822e1454cbef898f5d60421dee36c346a30df2a3f5b403d017db82e20` |
| `app/src/main/res/drawable/launcher_splash_split_background.xml` | `e82b39ab2d0d5ac4baa30a86c26272084cabc2d8ef98e0a268868db63246ee11` |
| `app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` | `4a012f5e590f47cb156001f499dfda675bd82fd17beeda4553606a7441eed1b5` |
| `app/src/main/res/raw/cool_music2.mp3` | `8739c47026ed62f4dde407a432d013b151af6d191a3d9a4fc5a0392c9071563e` |
| `app/src/main/res/raw/minik_kick2.mp3` | `d2a6e6eb3191c0498637b24897b420717bcae71c4b73f1ab5237db9c47a802f6` |
| `app/src/main/res/raw/sfx_finish.mp3` | `e5d4f4c8c99745d054493aeb5dc33ad30c0888777ccd327c9747c6ad45c406c1` |
| `app/src/main/res/raw/sfx_hit.mp3` | `de20197edd7aec007b8a3d2e45e6add57163b6878c446e71501e4b51f531980e` |
| `app/src/main/res/raw/sfx_pickup.mp3` | `e36d07f178d49a49ebebdd56ae26dcfd0b9e5a5e4f45024d9eae8ffbe7e8c8e9` |
| `app/src/main/res/raw/sfx_throw.mp3` | `3b5bf005e77004c80e785ad396a4d110f631dd35638117af6e356cfd9e1ad020` |
| `app/src/main/res/raw/sfx_wrong.mp3` | `c3af78f5f0a591aa006b0959aedaa8b20e0224bc7e1454857ac4784807cfd896` |
| `app/src/main/res/values-v31/styles.xml` | `7c02c8df11f62a4e358b1e4eee2561f35393b64525db03457931b7d5943a69a3` |
| `app/src/main/res/values/dialogs.xml` | `6f80ae8ee5c788dec2dba9c84e6dfe42fcf9766ebfc27656a4ada8b34969e018` |
| `app/src/main/res/values/firebase.xml` | `8e38fac936b53959cf609216c648e2044c295449bddcf53216cd1614f5d2db73` |
| `app/src/main/res/values/launcher_colors.xml` | `ff6071d12f1759813e670870c6bbfc08bc1f2658db72e1da838c8e34524559cf` |
| `app/src/main/res/values/styles.xml` | `f827af2dd356a385895e4de94da84bd44aa25f2c4f36cd1b959a23f70ec7cbfa` |
| `app/src/test/java/com/appsbybros/minik/localization/LanguageTest.kt` | `5117994247324664c1255499754de48c2b5c9fe40e2505c62f3656c0d53c8cb0` |
| `app/src/test/java/com/appsbybros/minik/localization/PresentationLanguageTest.kt` | `72f24ec485e3b6b25d0e85d39e8a34b44302eb166245ce5721c47357ae030079` |
| `app/src/test/java/com/appsbybros/minik/splash/MonetizationTest.kt` | `37433106f4d2fb75da8d3d192f0673696a1de89f2b9765637d6baad51f8b98bd` |
| `app/src/test/java/com/appsbybros/minik/splash/NetworkStateTest.kt` | `5bdfcb8b7d71d5c0d1cf6fee8b58a12250d8e84c07517830bb4ab73fe8b38b09` |
| `app/src/test/java/com/appsbybros/minik/splash/ReplicaEventsTest.kt` | `81f48b587afec128a2f8f3bbbcf80b9a27a01fcdbc4794363c0bd00cc903153b` |
| `app/src/test/java/com/appsbybros/minik/splash/ReplicaTimelineTest.kt` | `746bbe42f3d0ca7a4afbca2f919911c3a350320a7a38fa08b980c7a483676899` |
| `app/src/test/java/com/appsbybros/minik/splash/RevisionTest.kt` | `dcb6fbb39c1e2bf6e8b0ba901e277564241194450a509d8c10e8d6abbad24ad0` |
| `app/src/test/java/com/appsbybros/minik/splash/core/HouseSkillsTest.kt` | `0be8bdc8ed523516ba3e86216c054ed545158d73c1822737a563e4b73563263b` |
| `app/src/test/java/com/appsbybros/minik/splash/core/JourneyLanguageTest.kt` | `70e407c60a88ef10896ef02d5af0fe143db06d86bf08b503e57c42f39ddacf77` |
| `app/src/test/java/com/appsbybros/minik/splash/core/KnowledgeTest.kt` | `d14482431eb2f060ad8ede3a29ac41ee712fde729c43b32c811e1b503f86ca0f` |
| `app/src/test/java/com/appsbybros/minik/splash/core/LearningAcceptanceTest.kt` | `c30b1af916a28a339faa9634162dd9e7cbf9ad2e835081631cd7627add80dfcf` |
| `app/src/test/java/com/appsbybros/minik/splash/core/PaintFeedbackTest.kt` | `b0662d9d1ea6c3870492cfb2c2541b04cbe83d2e4bbd4ed2d60f6cd428a691d0` |
| `app/src/test/java/com/appsbybros/minik/splash/core/PresentationFeelTest.kt` | `6d1caaeb0650c0f4ca7104b9a30d64111b6b3baa494797ae4403c32e3a63e230` |
| `app/src/test/java/com/appsbybros/minik/splash/core/RoomInputPolicyTest.kt` | `aa7caa578ee4f7f949af9ae87d2c23ae539af1ebbf299845b1139f29b2aec9f8` |
| `app/src/test/java/com/appsbybros/minik/splash/core/RosterArrivalTest.kt` | `5e05de93b629bb9efe325b55a64929e12b90d9cb11cee5cedf1673e341a26f43` |
| `app/src/test/java/com/appsbybros/minik/splash/core/SplashCoreTest.kt` | `7d528449ec483ade512c4b2f06c6da3737f118fd2bec75c96a1a97a151c84282` |
| `app/src/test/java/com/appsbybros/minik/splash/core/SplashJourneyTest.kt` | `a5563034ae4a91168a2bb4fdb999dde6806528182185966eec90167bc71ec929` |
| `app/src/test/java/com/appsbybros/minik/world/ArenaCameraTest.kt` | `5c777ffa456bfdb0c53d6e8a32d9a9dae2a40e9a37f0b0c657041059e3cf1de3` |
| `app/src/test/java/com/appsbybros/minik/world/StableLabelsTest.kt` | `0c62659dbedfd8f7c9f11c330455781f76a4cba91fd78f9411212d0e03d6cb32` |
| `delivery/revision-2026-10-04/REPORT.md` | `2fac949228444a1b74a28d15662a5d7de199d242fddf2f7de848efb471418fd6` |
| `delivery/revision-sdk-branding-2026-10-04/STATUS.md` | `35e332e38b99b69b4f8cecafe7b5a8a622f3ed779b046967337f155929287ab5` |
| `firebase/database.rules.json` | `1f41be785e92a819592a3e8f74fbc61d20aada2bc9a8065527faf4e9ef02a0f3` |
| `firebase/firebase.json` | `7bed1c13d00ec37ca29856ff30af28f00f06509e5a925bc21d66527670dc94f9` |
| `firebase/rules-test.cjs` | `f60c522bfa5cc59b01d3a4ee4a87a895d8d38afe3b1f65b0c696d0a5ad01c856` |
| `firebase/start-emulators.ps1` | `28c3a00402243f93613c6d97a5eded2a27cb62ea3d243678bbc607c34c5d71f2` |
