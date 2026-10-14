# Multi Ping Pong (iOS) — port handoff

This document covers the iOS app target `MinikMultiPingPong` (bundle `com.appsbybros.minik.crosspong`, display name
"Multi Ping Pong"). It is a port of the Android app **Multi Ping Pong** (`C:\Projects\MinikCrossPong`, commit
`828c6fc094f3afb05d86fea0616704a17976dfaf`, brought up to commit `190871983cb5b72715604d1e48b6dd6bb6c8a22f` by the updates at
the end of this document, and to commit `5c1aa4dd4caea09de5e5a76f47199d21c4ba86eb` by the 2026-10-13 sync below): table tennis for 3 or 4 players on a cross-shaped table. Android forked that app
from **Modern Ping Pong** (`C:\Projects\MinikPingPong`, commit `7f5dd0a844ef8986eacd662f4afbbc34c7e92f56`). The iOS starting
point was `MultiPong/`, a copy of `Sources/ModernPong` that is compiled only into this target. The port keeps the Modern Ping
Pong type names (`MPController`, `MPEngine`, `ModernPongView` and so on), so the shared `Sources/**` code still compiles
unchanged:

- `ModernPongView(experience: .full, commerce: commerce)` is used by `Sources/PingPongOnlyRootView.swift`.
- `ModernPongView(experience: .simple, commerce: commerce) { result in … }` is used by `Sources/RetroPong/MathPingPongChooser.swift`.
- `ModernPongExperience` (`.full` / `.simple`) and `ModernPongResult` have the same declarations as before.

The Android repositories were used read-only. Nothing in them was changed.

## 2026-10-13 sync: Android 5c1aa4d

Source: `C:\Projects\MinikCrossPong` at commit `5c1aa4dd4caea09de5e5a76f47199d21c4ba86eb` ("Refine multiplayer teams,
character animation, menus and current store assets"). Its working tree is clean apart from an untracked `play-store` backup
folder. `git diff 1908719..5c1aa4d` touches 775 files; most are store listings and screenshots, website pages, QA evidence,
delivery folders and device tests. Those are not ported. The app files are listed with their hashes in "SHA-256 of the
Android files used" below. Committed on branch `port/multipong-1013`.

### Ported

| Android | iOS |
| --- | --- |
| Team play, 2 v 2 on the cross table: `cross/CrossTeams.kt`; team scoring in `CrossReferee.kt`; raised pass (double tap), set and swipe smash, team lesson, tap targets, practice aim, `localTeam` and `raised` on the wire in `CrossEngine.kt` / `CrossState.kt`; the team lesson card in `CrossTutorial.kt`; `CrossText.kt` | `MultiPong/CrossTeams.swift` (`CrossTeams`, `CrossTeamFlight`), `CrossReferee.swift`, `CrossEngine.swift`, `CrossState.swift`, `CrossTutorial.swift`, `CrossText.swift` |
| Reception assistance: `ReceptionAssist.kt` (shared slow-motion clock near the receiver), `ReceptionCamera.kt` (zoom); its sync in `CrossLink.kt`, `MatchLink.kt`, `FirebasePongRepository.kt` (`minikCrossPong/receptionPreferences/<uid>`), `PongRepository.kt`; the 2-player game in `ModernGame.kt` / `ModernCourt.kt` | `CrossReception` (`CrossTeams.swift`), `CrossReceptionCamera` (`CrossScene.swift`), `CrossLink.swift`, `MPMatchLink.swift`, `MPRepository.swift`, `MPEngine.swift` (`MPReceptionState`), `MPScene.swift`; settings in `MPXUI.swift` (`MPXReceptionSettings`) |
| Online team rooms: `cross/CrossTeamRoom.kt`, `CrossOnlineTeamsActivity.kt`, `TeamLineup.kt`, `TeamLobbyCards.kt`, `TeamPlayerIdentity.kt`; `firebase/cross-team.rules.json` | `MultiPong/CrossTeamRoom.swift` (same root `minikCrossTeams`, protocols `cross-teams-v1` and `cross-teams-v1-lobby-v2`, same paths and JSON bodies, host-simulated), `CrossLineup` and `CrossTeamIdentity` in `CrossTeams.swift`, `MPXTeams.swift`; `Tests/MultiPongFirebase/rules/cross-team.json` and two rule tests |
| Daily skill journey (30 stages, painted territory, stars and receipts) and the team match against house players: `cross/CrossPractice.kt`, `CrossJourney.kt`, `CrossJourneyActivity.kt`, `TeamVictoryView.kt`, `res/values*/journey.xml` | `MultiPong/CrossPractice.swift`, `MPXJourney.swift`, `MPXTeamVictory` in `MPXUI.swift`, `MPText.journeyTexts` |
| Character animation: `PongPlayerAtlas.kt`, `assets/pong-poses/*` (12-frame front, side and rear sheets, walk sheets, `atlas.json`); whole-body players, the local player from behind, the upper body over the table | `MPXPoseAtlas` and the players in `CrossScene.swift`; assets `mpx_pose_<id>`, `mpx_pose_<id>_walk`, `mpx_pose_atlas` (PNG sheets copied as they are) |
| Court: `cross/CrossCourt.kt` (sunset table, team territories, mesh nets, action camera, practice overlay, team scoreboard, tags), `MatchSceneLayout.kt` | `CrossScene.swift` (rewritten), `MPXMatchLayout` in `MPXUI.swift` |
| Tuning: `CrossShots.kt` pace scale 2.2 → 2.45; `CrossHouse.kt` house players wait near the arm end | `CrossShots.swift`, `CrossHouse.swift` |
| Menus and flows: `PlayActivity.kt`, `PrivateMatchActivity.kt`, `ModernActivity.kt`, `RoomBook.kt`, `KnockoutBracketView.kt`, `SettingSelector.kt`, `BotPicker.kt`, `ReadingPanel.kt`, `PongMenuMusic.kt`, `LocalizedActivity.kt` (sunset backgrounds) | `ModernPongView.swift`, `ModernPongRooms.swift`, `MPController.swift`, `MPPreferences.swift`, `MPXUI.swift`: remembered collapsible menu sections, the settings page (sounds, menu music, ball assistance; rating, sharing and feedback behind the grown-up question), team play in friendly games, the tournament save prompt, the remove button of the tournament list, the camera toggle and landscape hint, pose portraits as avatars |
| Texts: `AppText.kt`, `values*/strings.xml` | `MPTextCatalog.swift` regenerated (912 rows), `MPText.swift` |
| Art and sound: `cross_sunset_*.jpg`, `multiplayer_menu_landscape/portrait.png`, `team-celebration/*.webp`, `tournament_remove.webp`, `raw/pong_menu_remix.ogg`, the sunset logo | `mpx_sunset_*`, `mpx_menu_*`, `mpx_team_<id>` and `mpx_tournament_remove` (webp → PNG), `mpx_menu_music` (OGG → MP3, for `AVAudioPlayer`), the app icon (1024 px from `play-store/current/source/sunset-logo/master.png`, the source of Android's launcher icons) |
| Unit tests: `CrossTeamTest`, `CrossNetworkTeamsTest`, `CrossSetGestureRegressionTest`, `CrossTeamPaceRegressionTest`, `ReceptionAssistTest`, `TeamLineupTest`, `CrossPracticeTest`, `CrossShotsTest` | `Tests/MultiPongTests/CrossTeamTests.swift` (25 tests in three classes), `CrossPracticeTests.swift` (9), `CrossShotsTests.swift` (base pace 0.98) |

### Not ported

- Store listings, screenshots, website pages, QA evidence, delivery folders, `androidTest` device tests, Gradle and manifest
  changes, `BUILD_STATUS.md`.
- `AdCoordinator.java` and `MonetizationActivity.java`: Android ads and the family reminders that replace them belong to the
  Android build and to the shared family code.
- Code and art that 5c1aa4d no longer uses: `CourtPlayerArt.kt`, `WholePlayerArt.kt`, `JourneyCelebration.kt`,
  `assets/cross-art/*_directions.webp`, `assets/pong-art/whole-players.png`, `multiplayer_menu_players.png`.
- `MenuMoreFrame.kt` (the "more below" cue of the menu): it is shared family UI on Android; it was not added to this app.
- `firebase/tests/lineup.rules.test.cjs`: it reads the rules through absolute Windows paths of the Android machine.

### Deliberate differences

- The home-screen name stays "Multi Ping Pong" (`CFBundleDisplayName`, `project.yml` untouched): "Multiplayer Ping Pong" would
  be cut off under the icon. Inside the app the title is Android's new "Multiplayer Ping Pong".
- Online rooms (classic and team) stay off until this app has its `GoogleService-Info.plist`, as before;
  `CrossTeamRoom.make` returns nil without Firebase.
- The SpriteKit court draws Android's gradients and shadows with small textures and fills, so colours can differ slightly.
- On the two-player link a failed read of the reception preferences is ignored, and the match goes on without slow motion.
- Android's merged rules candidate at 5c1aa4d (`firebase-setup/merged-database-rules.json`) is older than its generator: its
  `minikCrossPong` has no `receptionPreferences`, although the fragment has it and both apps write there, and its
  `minikCrossTeams` differs from `cross-team.rules.json` in `lineup/.validate` and `phase/.write`. `rules/merged.json` is
  still a byte copy of that candidate, and the audit checks `receptionPreferences` in the fragment. Android's README says not
  to deploy a stale merged file.
- `Tests/MultiPongFirebase/tests/crosspong.test.cjs`: its isolation test also allows the new `minikCrossTeams` root, as
  Android's generator does; Android's copy of this test was not updated. Because the candidate is stale, its two `deepEqual`
  checks fail, here and on Android, until Android regenerates the candidate. The two team-room rule tests load
  `rules/cross-team.json` itself.
- The old 828c6fc art (`mpx_bot_*`, `mpx_legs_*`, `mpx_app_icon`) was removed from `MultiPongAssets`: nothing uses it any more.
  The `project.yml` comment that describes it was left as it is.

### Audit

`ANDROID_COMMIT` is now `5c1aa4dd4caea09de5e5a76f47199d21c4ba86eb`. New checks: the catalog parser follows the Android groups
in order (912 rows); `values*/journey.xml` against `MPText.journeyTexts`; the `minikCrossTeams` root in the merged rules and
`receptionPreferences` in the fragment; the team protocol name and root in `CrossTeamRoom.swift`; the 5c1aa4d assets.
`python Scripts/audit-multi-pong.py` and `python Scripts/audit-multi-pong.py --android C:/Projects/MinikCrossPong` pass (230
committed hashes at 5c1aa4d, 12 working-tree hashes). Every changed Swift file parses with tree-sitter-swift, and a scan finds
no line break inside a one-line string literal (tree-sitter accepts those; swiftc does not). A line-by-line compile review of
the changed Swift against the declarations it uses found four errors (a `camera` property that clashed with `SKScene.camera`,
two `guard let` rebindings of a local in the same scope, line breaks in a string), all fixed. Nothing has been compiled or
run: this Windows machine has no Swift toolchain.

## What changed in this repository (all uncommitted)

| Area | Files |
| --- | --- |
| New game core | `MultiPong/CrossGeometry.swift`, `CrossBall.swift`, `CrossReferee.swift`, `CrossShots.swift`, `CrossHouse.swift`, `CrossEvents.swift`, `CrossState.swift`, `CrossEngine.swift`, `CrossMatch.swift`, `CrossLink.swift`, `CrossText.swift`, `CrossTutorial.swift` |
| New court renderer | `MultiPong/CrossScene.swift` (SpriteKit) |
| New tournament logic | `MultiPong/MPGroupMatch.swift` |
| New room UI | `MultiPong/ModernPongRooms.swift` |
| Rewritten | `MultiPong/MPMultiplayerModels.swift`, `MPKnockout.swift`, `MPController.swift`, `ModernPongView.swift` |
| Edited | `MultiPong/MPRepository.swift`, `MPMatchLink.swift`, `MPEngine.swift`, `MPPreferences.swift`, `MPAds.swift` |
| Resources (this app only) | `Resources/MultiPongAssets.xcassets`: `mpx_app_icon` plus the `mpx_legs_*` and `mpx_bot_*` sheets of amber, comet, flare, gaya, june, mia and moshiko, converted from the Android `webp` files to PNG (all removed by the 2026-10-13 sync: the court now draws the pose sheets) |
| Project | `project.yml`: one entry in the `MinikMultiPingPong` sources, `Resources/MultiPongAssets.xcassets` (resources build phase) |
| Unit tests | `Tests/MultiPongTests/*.swift` (`MultiPongAppTests.swift` kept as it was) |
| Firebase rules mirror | `Tests/MultiPongFirebase/**` |
| This document | `docs/multi-pong-ios-handoff.md` |
| Audit script | `Scripts/audit-multi-pong.py` |

`git status` also lists `MultiPong/MPTuning.swift` as modified, but `git diff` shows no content change. The file's line
endings differ from what `core.autocrlf` expects, and that is the only difference.

Nothing under `Sources/**`, `Sources/ModernPong/**`, other targets, other apps' resources, workflows or other scripts was
touched.

Regenerate the Xcode project with XcodeGen (`xcodegen generate`) before building, because `project.yml` gained the asset
catalog.

## Android → iOS mapping

| Android (828c6fc, `app/src/main/java/com/appsbybros/minik/pingpong/`) | iOS (`MultiPong/`) |
| --- | --- |
| `cross/CrossGeometry.kt` | `CrossGeometry.swift`. It also holds the rest of Kotlin `Random` on top of `MPKotlinRandom`, `crossMod` and `crossFold`. |
| `cross/CrossBall.kt` | `CrossBall.swift` |
| `cross/CrossReferee.kt` | `CrossReferee.swift` |
| `cross/CrossShots.kt` (shots, `AimMap`) | `CrossShots.swift` (`CrossShots`, `CrossAimMap`) |
| `cross/CrossHouse.kt`, `HouseStrategy.kt`, `RallyVariation.kt`, `ActorPresentation.kt` (timing) | `CrossHouse.swift` (`CrossHouse`, `CrossStrategy`, `CrossVariation`, `CrossMotion`, `CrossForecast`, `CrossActor`, `CrossHouseStrategy`, `CrossServeReliability`) |
| `cross/CrossEvents.kt` (`CrossEvent`, `Cue`, `CrossSoundPolicy`) | `CrossEvents.swift`. Cues map onto the existing `MPAudio` samples. |
| `cross/CrossState.kt` (wire format, protocol 2) | `CrossState.swift` |
| `cross/CrossEngine.kt` | `CrossEngine.swift` |
| `cross/CrossMatch.kt` (stages, elimination, goals) | `CrossMatch.swift` |
| `cross/CrossLink.kt` (checkpoints, actions, authority) | `CrossLink.swift` |
| `cross/CrossText.kt` | `CrossText.swift` (EN/HE verbatim) |
| `cross/CrossTutorial.kt` | `CrossTutorial.swift` |
| `cross/CrossCourt.kt`, `BotArt.kt`, `SpriteSampling.kt`, `MinikMotion.kt` (cross parts) | `CrossScene.swift` |
| `cross/CrossActivity.kt` | `MPController.swift`: local cross game, tour, settings, result, pause and restart. `ModernPongRooms.swift`: `crossGame`, `crossSettings`, tour cards and result view. |
| `multiplayer/PlayActivity.kt` | `ModernPongView.swift` (home, controls, house-player carousel, profile, create/join forms, room lists, help, result) and `ModernPongRooms.swift` (lobby, seat lobby, tournament roster, play list, bracket, group bracket, standings). Flow logic is in `MPController.swift`. |
| `multiplayer/PrivateMatchActivity.kt` | `MPController.launch` and `MPMatchLink.swift` (classic two-player fixtures), `ModernPongView.classicMatchScreen` |
| `multiplayer/PongModels.kt` (`Session`, `MatchRecord`, `PongRules`), `CrossFixture.kt`, `ControlChoice.kt` | `MPMultiplayerModels.swift` (`MPSession`, `MPFixture`, `MPRules`, `MPSequenceGate`, …), `MPGroupMatch.swift` (`MPCrossFixture`), `MPKnockout.swift` (`MPControlChoice`) |
| `multiplayer/GroupMatch.kt` | `MPGroupMatch.swift` (`MPGroupTournament`, `MPTableSimulation`) |
| `multiplayer/Knockout.kt`, `CompletionText.kt`, `MatchText.kt` | `MPKnockout.swift` (`MPKnockout`, `MPCompletionText`, `MPMatchText`, `MPKotlinRandom`) |
| `multiplayer/KnockoutBracketView.kt` | `MPKnockoutBracketView.swift` (classic bracket) and `ModernPongRooms.groupBracket` (group tables per round) |
| `multiplayer/PongCodec.kt`, `PongRepository.kt`, `FirebasePongRepository.kt` | `MPRepository.swift` (`MPCodec`, `MPRepository`, `MPLocalRepository`, `MPFirebaseRepository`, `MPRepositoryOrder`) |
| `multiplayer/MatchLink.kt` | `MPMatchLink.swift` |
| `multiplayer/BotRoster.kt` | `MPRoster.swift` (unchanged) and `MPRules.housePlayer` / `copyNumber` (house copies "Kyra 2", …) |
| `multiplayer/RoomBook.kt` | `MPPreferences.swift` (saved rooms, completion and celebration flags) |
| `multiplayer/LobbyAudio.kt`, `LobbyEvents.kt` | `MPController.lobbyCues` + `MPAudio` |
| `multiplayer/Nicknames.kt` | `MPNames` in `MPPreferences.swift` (existing) |
| `multiplayer/ExpandButton.kt`, `MenuExpansion.kt`, `MenuScrollView.kt`, `SettingSelector.kt`, `BotPicker.kt`, `HousePlayerPicker.kt`, `GuideDialog.kt` | SwiftUI equivalents in `ModernPongView.swift` (`expandHeader`, `controls`, `carousel`, `housePicker`, `help`) |
| `VictoryConfetti.kt` | `MPVictoryConfetti` (existing, `MPKnockoutBracketView.swift`) |
| `ModernEngine.kt`, `ModernGame.kt`, `ModernEvents.kt`, `Tuning.kt`, `ModernTutorial.kt`, `ModernCourt.kt`, `ModernAudio.kt` | Classic two-player game kept from Modern Ping Pong: `MPEngine.swift`, `MPPhysics.swift`, `MPTuning.swift`, `MPTutorial.swift`, `MPScene.swift`, `MPAudio.swift`. The fork's changes are ported: `suddenDeath` (1:0 tie-break), `alternateServe`, and the Beginner aim reset. |
| `LocalizedActivity.kt` | The `hebrew` flag from the app language, with RTL layout (since 2026-10-04: `MPText`, six languages; see the update at the end) |
| `NetworkState.kt` | The repository connection state (`connected` / `connecting`, offline note) |
| `monetization/*` | Not ported (see below). `MPAds` has no ad unit. |

## Feature inventory

**Ported**

- **The 3/4-player game:**
  - Geometry: arms, territories, radial nets, centre post, and the round hub for 3 players.
  - Ball physics in fixed 1/120 s substeps.
  - Referee: a miss gives the striker +1 and the responsible receiver −1; a fault costs only its owner 1; nobody drops below 0. The serve rotates every rally. Each rally resolves exactly once. Classic and elimination scoring.
  - Shots and aiming (Beginner, Standard, Pro), house players (strategy, variation, serve reliability, timing), the cross guide (tutorial drills and the guided tour), and the event and sound policy.
- **Court (SpriteKit):**
  - Per-seat rotation (your seat at the bottom), and an overview / full-screen camera toggle that is remembered (`MPPreferences.crossFullScreen`).
  - Scoreboard, name tags, +1/−1 notes, receiver highlight, an off-screen ball arrow, and upright characters with legs.
  - Pause, restart and settings: players, control, target, opponents.
- **Home and flows, as on Android:**
  - Friendly tables of 2, 3 or 4 seats, with a seat lobby (take or change your own seat; the host places house players).
  - Tournaments of classic pairs (round robin 2–8, knockout 2–9) or group tables of 3/4 (round robin 3–8, knockout 3–32), including the elimination game type.
  - Group round-robin points 3/2/1/0, group-knockout "top two" with tie-breaks, duels and walkovers, and knockouts of any size.
  - The classic bracket and the group bracket.
  - A court pauses while a human of the fixture is away, and resumes from the latest checkpoint after the app returns from the background.
  - Completed entries are not kept in the saved-room list.
  - Completion texts, headlines and confetti.
- **Online code:**
  - The Firebase root is `minikCrossPong`, under the Android app name `minik-cross-pong`.
  - The wire format and the CrossLink protocol (protocol-2 checkpoints, the actions ring with seat/stage/rallyId/hitIndex/strike, `MPSequenceGate`, authority = smallest human uid) are byte-compatible with Android records.
  - Firebase arrays and index maps are both accepted, and so are legacy `a`/`b` pair records.
- **Offline:**
  - Without a `GoogleService-Info.plist` for `com.appsbybros.minik.crosspong`, `MPFirebaseRepository.configured()` returns nil and the app uses `MPLocalRepository`.
  - Nothing crashes. Practice, local cross games, the guide, local friendly tables with house players and the house-only tournaments all work.
  - The forms show the Android offline note. Join says "Online rooms are not available in this version yet."
- **Ads and purchases off:** there is no ads or purchase UI and no ad request (`MPAds.interstitialUnit` is always nil, so the Google SDK is never started from `MultiPong/`).
- **Texts:** English and Hebrew are verbatim from Android, with RTL. Since the 2026-10-04 update (end of this document) also
  Spanish, Arabic, Hindi and Dutch from Android's catalog, with RTL for Arabic too.

**Partial**

- **Online play is ported but dormant.** No Firebase registration file for `com.appsbybros.minik.crosspong` exists in `Config/Firebase/`, and none was added: creating one would need the Firebase console or API, which this port was not allowed to use. Online rooms start working once a plist for that bundle id (project `minikswish`) is placed in the target's resources. `MPFirebaseRepository.configured()` checks the bundle id and the project. The database rules candidate (`Tests/MultiPongFirebase/rules/merged.json`) has not been deployed.
- **Art.**
  - The seven characters with Android legs sheets use the Android body and legs art (`mpx_*`).
  - Kyra, Coach67 and Miniko use the existing shared Modern Ping Pong atlases (`mp_bot_*`) without separate legs, as before.
  - Fonts, exact sizes and colours follow SwiftUI/SpriteKit defaults close to Android, not pixel-identical.
- **Commerce.** `Sources/RootView` (shared, not editable here) may still start the shared commerce controller for this product variant. Multi Ping Pong shows no purchase UI and makes no ad request, but a StoreKit product query by shared code is outside `MultiPong/`. Check this when App Store products exist.

**Not ported, and why**

- **Android monetization:** `monetization/*`, `AdCoordinator`, `RemoveAdsBilling`, `MonetizationActivity`, access codes and `monetization-backend/`. The task requires ads and purchases off.
- **Android device QA tooling** (`tools/*.cjs`, `firebase.device-qa.json`): this is Android/ADB-specific.
- **Rules generator and production reader** (`firebase/generate-rules.cjs`, `knockout-rules.cjs`, `read-production-rules.cjs`, `live.rules.template.json`): the iOS mirror stores their outputs (`rules/crosspong.fragment.json`, `rules/merged.json`, `rules/current.json`) and never reads or deploys production.
- **Android-only unit tests:** monetization, Firebase activation through Gradle properties, sprite sampling of Android bitmaps, and the Modern Ping Pong engine tests that are unchanged in the fork. See the test section.

## Decisions

- **Invalid input is clamped, not rejected.** Where Android `require`s valid input (geometry seat count, referee target, classic scoring with more than two players, start scores, match goal), the Swift port clamps or corrects the value instead of throwing. A corrupt online record can therefore never crash the court. Restores of checkpoints still throw (`CrossStateError`) and are rejected as a whole, as on Android.
- **CrossLink constructor.** The four Android `require`s in the `CrossLink` constructor (2–4 players matching the match, seat
  kinds in fixture order, the fixture's first server, a networked match when there are remote humans) are not repeated in
  Swift. `MPController` always builds the match from `CrossLink.seats` and `CrossLink.firstServer`, so they hold by
  construction.
- **CrossLink writes outlive the link.** The checkpoint, action and result writes run in `Task`s that hold the link
  strongly, as the Kotlin repository callbacks do. The last checkpoint written by `close()` therefore still reaches the
  database when the owner drops the link immediately (`crossLink?.close(); crossLink = nil`).
- **Tolerant records.** `MPBot` and `MPIdentity` decode like Android `PongCodec.bot` / `PongCodec.identity`:
  - A missing stat reads as 5 and a missing skill as the accuracy.
  - Every decoded value is `safe()`.
  - One older or partial house record can no longer fail the whole participants map of a room.
  - A new duel fixture stores its authority like every other fixture.
- **Android behaviour restored after review:**
  - **Local repository** (`MPLocalRepository`):
    - It reads its store on every call, so two instances agree.
    - It refuses a duplicate code.
    - It stamps creation and activity times, but `mutate` stamps activity only on a real change.
    - It keeps checkpoints only in UserDefaults, refuses to store a non-plist value, and removes them on leave.
  - **Room flows:**
    - `refreshRooms` skips failures instead of failing as a whole.
    - A failed room transition only affects the room still shown, and `maybeStart` is revisited only after a success.
    - Returning from the background reattaches the full room observer without stale cues.
    - A friendly house player's seat is chosen inside the transaction.
  - **Forms and results:**
    - Friendly rooms are created with legs 1 and win points 3.
    - "Points to win" opens at 7.
    - A finished local match does not show its result again after the guide.
- **Kotlin `Random` parity.** `MPKotlinRandom` replays `kotlin.random.Random(seed)` (XorWow) exactly: `nextInt`, `nextInt(until)`, `nextDouble`, `nextDouble(from, until)`, `nextBoolean`, `nextLong`, `shuffled`, `random`. Seeded house players, table simulations and knockout draws therefore choose as on Android. The values were checked against kotlin-stdlib 2.1.0 (see `KotlinRandomParityTests`).
- **Classic first server.** The first server of an online classic fixture is the authority, as in the Android rule. The old iOS copy used `match.a`.
- **Local strike identity.** Android publishes a local strike when it is a new object (`!==`). iOS numbers strikes (`CrossEngine.localStrikeID`) instead.
- **Live action order.** Buffered live actions are applied in (rallyId, hitIndex, sequence) order (`MPRepositoryOrder`), which also covers Firebase delivering children out of order.
- **Presence.** Lobby presence follows Android `syncLobbyPresence`. iOS uses one presence for lobby and court, so a court about to launch keeps it rather than dropping and reopening it.
- **Re-entrancy.** `MPLocalRepository` notifies synchronously, so presence acquisition and release, and `MPSubscription.close`, are re-entrancy safe.
- **Assets.** The Android `webp` files were converted to PNG, giving about 21.8 MB.

## iOS differences

- **Rendering.** SpriteKit replaces Android Canvas. The table outline is unioned with `CGPath` set operations (iOS 16+), the far end of the table is drawn with the same perspective factor, and the full-screen camera follows the local seat.
- **Navigation.** Navigation is SwiftUI routes (`MPRoute`) instead of Android activities. Back follows the Android order.
- **Language.** Hebrew comes from the app or system language rather than an in-app language activity. Since the 2026-10-04
  update the app follows the primary device language like Android `LocalizedActivity` (see that section).
- **Lifecycle.** The app returning to the foreground re-opens the room observer and, for a fixture court, returns to the lobby. The court then re-opens from the latest checkpoint, like Android `onResume`.

### Known smaller differences

These were found in review and left as they are. None affects scoring, the wire format or the rules.

- **Court:**
  - When the engine is swapped (an elimination stage change), `CrossScene` cancels the touch in progress and clears the floating +1/−1 notes. Android keeps both.
  - The ball shadow is a solid ellipse rather than Android's radial gradient.
  - A room's cross match screen also shows the overview / full-screen button.
- **Lists:**
  - The friendly participant row and the house-player and "mine" lists are ordered by id. Android uses map order.
  - The profile avatar is picked from a grid instead of Android's house-player picker with a "Use this character" button.
- **Records:**
  - `MPSession` decodes `participants`, `connections` and `seats` as whole maps: one malformed entry empties that map. Android decodes them entry by entry.
  - A house profile outside the roster (impossible in the new `minikCrossPong` namespace) uses the roster tuning formula, not Android's generic accuracy formula.
- **Local (offline) repository, inherited from Modern Ping Pong iOS:**
  - Presence is one slot per player, not one token per subscription.
  - `observe` sends nothing for a missing room.
  - `leave` drops a local tournament instead of applying the tournament leave rules.
  - A duplicate code reports the generic error text.
- **Controller messages and flows:**
  - A classic match-link error shows as an alert, not as the inline warning line.
  - Cross-link failures show "Connection interrupted…" rather than the raw message.
  - There is no dedicated "Another player connected" text when a delete is refused.
  - A new identity starts at nickname 0 instead of a random one.
  - A fixture that finishes while the app is in the background shows the room on return, not the result dialog.
- **Classic engine** (unchanged `Sources/ModernPong` behaviour):
  - House controls apply only when the engine has a bot.
  - The lowest level has no separate "move the paddle" status.
- **Pure-function differences** that tests document:
  - Invalid group-table shapes return an empty design or simulation instead of throwing.
  - `MPMatchText` has no `standing` builder and no three-argument `summary` builder. Neither is used by the Android UI.

## Tests

### Unit tests (`Tests/MultiPongTests`, target `MultiPongTests`, `@testable import MinikMultiPingPong`)

The suite has 291 ported XCTest methods plus the existing `MultiPongAppTests`. Every method names its Kotlin original in a
`// Kotlin: <name>` comment. Where Kotlin `require`s and Swift clamps, the test asserts the clamped value; each such
place is commented "Swift clamps instead of throwing". Kotlin assertions that cannot run on iOS are written as
`// Not ported: <name> — <reason>` comments. Shared helpers (Kotlin `CrossTestSupport.kt` and `CrossEngineSupport.kt`)
live in `CrossTestSupport.swift`.

| Kotlin test (828c6fc) | Swift file | Ported / Kotlin |
| --- | --- | --- |
| `cross/CrossGeometryTest` | `CrossGeometryTests` | 12/12 |
| `cross/CrossBallTest` | `CrossBallTests` | 13/13 |
| `cross/CrossRefereeTest` | `CrossRefereeTests` | 19/19 |
| `cross/CrossShotsTest` | `CrossShotsTests` | 15/15 |
| `cross/CrossBeginnerAimTest` | `CrossBeginnerAimTests` | 3/3 |
| `cross/CrossControlTest` | `CrossControlTests` | 12/12 |
| `cross/CrossHouseTest` | `CrossHouseTests` | 8/8 |
| `cross/CrossEventsTest` | `CrossEventsTests` | 3/3 |
| `cross/CrossRallyTest` | `CrossRallyTests` | 3/3 |
| `cross/CrossExerciseTest` | `CrossExerciseTests` | 3/3 |
| `cross/CrossMatchTest` | `CrossMatchTests` | 7/7 |
| `cross/CrossModesTest` | `CrossModesTests` | 10/10 |
| `cross/CrossNetworkTest` | `CrossNetworkTests` | 9/9 |
| `cross/CrossLinkTest` | `CrossLinkTests` (in-file fake repository) | 11/11 (two constructor `assertThrows` not ported) |
| `cross/CrossAdversarialTest` | `CrossAdversarialTests` | 24/24 |
| `multiplayer/GroupTournamentTest` | `GroupTournamentTests` | 12/12 |
| `multiplayer/GroupMatchModelTest` | `GroupMatchModelTests` | 16/17 (`lobbyReadyCueListensToEverySeat`: the cue logic is private in `MPController`) |
| `multiplayer/GroupMatchAdversarialTest` | `GroupMatchAdversarialTests` | 15/15 (two partial) |
| `multiplayer/MatchTextTest` | `MatchTextTests` | 4/4 (`standing` and the 3-argument `summary` builders do not exist on iOS) |
| `GameModeTournamentTest` | `GameModeTournamentTests` | 19/19 |
| `ClassicTiebreakTest` | `ClassicTiebreakTests` | 3/3 |
| `ClassicFixesTest` | `ClassicFixesTests` | 2/2 |
| `KnockoutTest` | `KnockoutTests` | 12/12 |
| `MultiplayerTest` | `MultiplayerTests` | 20/20 |
| `RoomPolicyTest` | `RoomPolicyTests` | 5/6 (`noticesUseStableMatchIds…`: iOS retired the notice book; nickname validator checks not ported) |
| `LobbyPauseTest` | `LobbyPauseTests` | 2/2 |
| `TournamentUpdateTest` | `TournamentUpdateTests` | 7/8 (LobbyEvents / RoomStartGate are private `MPController` state) |
| `FriendlyFlowTest` | `FriendlyFlowTests` | 3/3 |
| `UnifiedFriendlyTest` | `UnifiedFriendlyTests` | 3/3 |
| `BotRosterTest` | `BotRosterTests` | 8/9 (atlas cell mapping is private in `CrossScene`) |
| `PeerMatchTest` | `PeerMatchTests` (in-file fake repository) | 3/3 |
| — (iOS only) | `KotlinRandomParityTests` | 5 (reference values from kotlin-stdlib 2.1.0) |

**Not ported**

- **Monetization tests** (`monetization/*Test.java`, 59 tests): ads and purchases are off in this app.
- **`FirebaseActivationTest`** (Gradle properties) and **`SpriteSamplingTest`** (Android bitmaps): these are Android-only. The iOS equivalents are `Tests/MultiPongFirebase/tests/configuration.test.cjs` and the asset catalog.
- **The unchanged classic-engine tests:**
  - `ModernEngineTest`, `ModernDifficultyControlTest`, `ModernFollowupTest`, `ModernRefinementTest`, `ModernTutorialTest`, `SwipePhysicsTest`, `ServeFlightRegressionTest`, `PointPowerTest`, `PracticeRallyTest`, `BeginnerAndStrategyTest`, `MinikMotionTest`, `ControlAndCompletionRegressionTest` and `ProfileAvatarTest` (102 tests).
  - These files are byte-identical to Modern Ping Pong `7f5dd0a`. Their iOS counterpart is the classic engine `MPEngine`, which is unchanged from `Sources/ModernPong` apart from the fork's three changes (sudden-death tie-break, alternating network serve, Beginner aim reset). That engine has no XCTest suite in this repository either.
  - Its seeded RNG (`MPRandom`) is not Kotlin's `Random`, so most of these exact-rally tests would need redesign rather than a port.
  - The three fork changes are covered by `ClassicTiebreakTests`, `ClassicFixesTests`, `MultiplayerTests` and `PeerMatchTests`.
  - Porting them was started but stopped by the account usage limit. Suggested follow-up.

**Expected to differ at runtime** (faithful assertions kept):

- **The bidi tests** in `MatchTextTests`, `GroupTournamentTests` and `GroupMatchModelTests` lay out text with CoreText instead of `java.text.Bidi`. They need CoreText to treat Unicode isolates the way Java does.
- **Statistical tests seeded through `MPRandom`** (`BotRosterTests`, `ClassicFixesTests`) keep only Kotlin's bounds.
- **Long simulations** (`CrossAdversarialTests`, `CrossMatchTests`, `GameModeTournamentTests`, `GroupMatchAdversarialTests`, `CrossLinkTests`) take tens of seconds in a Debug simulator build.

Nothing here has been compiled or run. This Windows machine has no Swift toolchain. The checks that were run are listed below.

### Firebase rules (`Tests/MultiPongFirebase`)

The folder mirrors the Android `firebase/` verification:

- **`rules/`**
  - `merged.json`: byte-identical to `firebase-setup/merged-database-rules.json`.
  - `current.json`: the live-rules snapshot the merge was checked against.
  - `crosspong.fragment.json`
- **`tests/`**
  - `crosspong.test.cjs` and `pingpong-regression.test.cjs`: verbatim except for the three rule-file paths.
  - `configuration.test.cjs`: rewritten for iOS. It checks the `minikCrossPong` root, the `minik-cross-pong` app name and the bundle id in `MPRepository.swift`, the closed root, and this folder's emulator configuration.
- **`firebase.json`** (database emulator on 127.0.0.1:9000) and **`package.json`** (`npm run test:emulator` with `--project demo-minik-crosspong`).

Result on 2026-10-03, local Firebase RTDB emulator only: **64 tests, 64 passed, 0 failed**.

- The run used the Android `firebase/node_modules` (firebase-tools 15.31.0, cached database emulator v4.11.2) through `NODE_PATH` and JetBrains Runtime 21.
- Isolation:
  - It ran from a scratch copy of the folder, with an empty firebase-tools configstore (no login token, MOTD marked fresh).
  - A preloaded Node guard refused every non-loopback DNS lookup or socket in every Node process. Its log stayed empty.
  - Nothing was deployed, and no Firebase or Google service was contacted.

To rerun on a Mac, from the folder:

```sh
npm ci
npm run test:emulator
```

## Checks run

- **Syntax:** every `MultiPong/*.swift` and `Tests/MultiPongTests/*.swift` file parses without errors with tree-sitter-swift. Bracket balance was checked as well (`Scripts/audit-multi-pong.py`).
- **Compile review:** line-by-line, against the real declarations, for all new and changed production files and all test files. Definite compile risks were fixed (expression splits for the type checker). Doubts are listed in the final report.
- **Static audit:** `python3 Scripts/audit-multi-pong.py [--android <MinikCrossPong checkout>]` checks:
  - the shared entry points;
  - the Firebase root and registration;
  - that no ad unit is configured;
  - the rules-mirror hash;
  - `@testable` imports;
  - bracket balance;
  - optionally, every Android SHA-256 below (all 138 matched).
- **Kotlin `Random` parity:** the Swift algorithm was replayed in Python and compared with values printed by kotlin-stdlib 2.1.0 on the JBR, for int seeds, negative seeds and long seeds. They are identical.
- **Firebase rules:** passed in the local emulator, as above.


## SHA-256 of the Android files used

Hashes are of the committed blobs at `5c1aa4d` (`git show 5c1aa4d:<path> | sha256sum`), the Android commit this port matches
since the 2026-10-13 sync; `python3 Scripts/audit-multi-pong.py --android <MinikCrossPong>` re-hashes them at its
`ANDROID_COMMIT`. The original port read these files at `828c6fc`, and the 2026-10-07 update at `1908719`. 38 of the files
below changed between `1908719` and `5c1aa4d`; the 2026-10-13 sync at the top of this document says what was ported from
them. The files added since `828c6fc` are listed at the end, those added since `1908719` last. The working copies on the
Android machine have CRLF line endings, so their working-file hashes differ. `MinikPingPong@7f5dd0a` was used only as the diff
base, to find what the fork changed, and is not listed.

Kotlin sources (all of app/src/main/java/com/appsbybros/minik/pingpong) (57 files):

```text
97e6c175c9bcfde4eb07e42150a9b5306e889cca8ed46df5c74446a49947a197  app/src/main/java/com/appsbybros/minik/pingpong/ActorPresentation.kt
53411f3236c67bf7edfa5ff798e653332114c480b33d2dd4598cbbe14dfa3ca4  app/src/main/java/com/appsbybros/minik/pingpong/BotArt.kt
6316c60e10bdc428d1c08a1898abf466a61fdee18d4652b1fa91a499742074dc  app/src/main/java/com/appsbybros/minik/pingpong/BotPicker.kt
fdfebcabec8852c833c5532d0d0aab05b6603f42ddd20eca724d8482ce036238  app/src/main/java/com/appsbybros/minik/pingpong/GuideDialog.kt
a237466a01c684e2af095fbba55c7e29d950eed58640485f6f56236e26de586a  app/src/main/java/com/appsbybros/minik/pingpong/HousePlayerPicker.kt
b490e3c79d8b28314c6f1c966ea350a744e9bbcfdc92f3d5bae242bac9766989  app/src/main/java/com/appsbybros/minik/pingpong/HouseStrategy.kt
da4ab8e6825bb4b62a3336d4911f8484e914db0fb65050e93285739e37629f78  app/src/main/java/com/appsbybros/minik/pingpong/LocalizedActivity.kt
f152395827b3e876c91159278332b85023acb71a3a6633cfd2f183af1ee02bec  app/src/main/java/com/appsbybros/minik/pingpong/MinikMotion.kt
3363065ffdd13048f5c6ceda8555cdb011ba09c8aa503868c2153cc58b504d7e  app/src/main/java/com/appsbybros/minik/pingpong/ModernActivity.kt
8c3d6bc0c7891ab7143223269b28057106d142cf7c26ceea7bfe4e4d5086ca25  app/src/main/java/com/appsbybros/minik/pingpong/ModernAudio.kt
c1634ba1dfac0b271e9be1a7ae1ed5f2d154b81610aea605593094ac23d9e6f1  app/src/main/java/com/appsbybros/minik/pingpong/ModernCourt.kt
1dbfeb8393f3eaebc673d566819a1446742302633e85c387491b892a13460e48  app/src/main/java/com/appsbybros/minik/pingpong/ModernEngine.kt
ba7e218ec5a9bb30448306d90d44ac14808d4648cd02c6f57f5c43962950ab45  app/src/main/java/com/appsbybros/minik/pingpong/ModernEvents.kt
fd3d0001f76bd05107e332d75ec448704fdbddce900959742f099995954c4fa4  app/src/main/java/com/appsbybros/minik/pingpong/ModernGame.kt
2dc6e620d4fffe644beff37ec3efc4cc7255b3036db01abd34c4a6c5407cb3e7  app/src/main/java/com/appsbybros/minik/pingpong/ModernTutorial.kt
226aa095b7d6b860125859a70e25125b1203789058659d870a58ca1daaf7ac44  app/src/main/java/com/appsbybros/minik/pingpong/NetworkState.kt
948f4ce9e37c370e52ddfa428ee195aabbf0067aa169a2d0509554cda0370dc0  app/src/main/java/com/appsbybros/minik/pingpong/RallyVariation.kt
ce317e516ea428a3c681a41f0653ffe6a58fd6d84450adf8cdad8469740f179a  app/src/main/java/com/appsbybros/minik/pingpong/SettingSelector.kt
d657d63391fbd3002c38933b847fabb89a1bf0291c3a439a7a7402806782e5ed  app/src/main/java/com/appsbybros/minik/pingpong/SpriteSampling.kt
d8791489501a20a8f3694bdd901c36b49915e6ac5e233cd767f088d15acb16cb  app/src/main/java/com/appsbybros/minik/pingpong/Tuning.kt
37be9d496034a3b9aaaac518077d62146996270c88a50fc828d9972547a55d4a  app/src/main/java/com/appsbybros/minik/pingpong/VictoryConfetti.kt
9e688d9ce87d723772f6a3bffb5b66b3e23c64477643752476e8643dee95c30d  app/src/main/java/com/appsbybros/minik/pingpong/cross/CrossActivity.kt
ba5bfe0e3638e7b18e753139197b573ed3f495ffa21c2c83bceff0df01acb0b5  app/src/main/java/com/appsbybros/minik/pingpong/cross/CrossBall.kt
cf0b61f8125aab1c225154c05980f1a66dbac2c156d8ded13bf59712f49f13ec  app/src/main/java/com/appsbybros/minik/pingpong/cross/CrossCourt.kt
78aafceec5f9563151bc47ba750c9a49be0f1fa45465520f8ad70a1714a8f10c  app/src/main/java/com/appsbybros/minik/pingpong/cross/CrossEngine.kt
ecd8868d326a0d57dc672db01b04d5dc54ec86c62c6e8035a658d09ae8f03dcc  app/src/main/java/com/appsbybros/minik/pingpong/cross/CrossEvents.kt
191f173cbbcb4c5ccb668dfec2dd9e47dd6ee073c233911496fc8ff584d77fa8  app/src/main/java/com/appsbybros/minik/pingpong/cross/CrossGeometry.kt
fdbb018a560d4ff0f9ea4bf0e05610cc28eb693270d973871092dfa8a37703a0  app/src/main/java/com/appsbybros/minik/pingpong/cross/CrossHouse.kt
e5047b87a691b317f54b625f98e2835371806c8482776d084308d6a42fe3e633  app/src/main/java/com/appsbybros/minik/pingpong/cross/CrossLink.kt
a12f2a0ace4d02acc6fe8d12e8a3f73e7d9e9236db36f00070c66c274347cafd  app/src/main/java/com/appsbybros/minik/pingpong/cross/CrossMatch.kt
13287205caac3dc878c6f6100ff153e61bd6ee874fdc93cc3b8f981d5956255b  app/src/main/java/com/appsbybros/minik/pingpong/cross/CrossReferee.kt
7e79424fbee5ad294e5d05e6d5149b88082634817233ac9007b30c507ec1ed04  app/src/main/java/com/appsbybros/minik/pingpong/cross/CrossShots.kt
5bfb7533c6d8948f0dd6cda0179270da7bf770f1e3a902787adf4b66095541a2  app/src/main/java/com/appsbybros/minik/pingpong/cross/CrossState.kt
7ab7eabcd361731124d839d9d299d47eaa3c7abe4ed803b7d9dd89cdde5cd5aa  app/src/main/java/com/appsbybros/minik/pingpong/cross/CrossText.kt
d6e14e8d5f475287a1de9401385b752ed6bf26711b12ff87ad1794b1309171d8  app/src/main/java/com/appsbybros/minik/pingpong/cross/CrossTutorial.kt
8e1908d4c70eef01554e4f791a682e5a348a3995a4585abbbb89af3fbd51a6cf  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/BotRoster.kt
d1dee0c8e77dec54ba07f6974fc273b91a68b5e8e5ad3aeef7105614c908030d  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/CompletionText.kt
4bb38dab3c7ec0ec8c6925a4fbaca0058d75d70cda96af09c707c878a433ae19  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/ControlChoice.kt
02675891e0d31c9999770178c72b6d41a5271672c11737e73b3d91448ab3289a  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/CrossFixture.kt
24f8cab6dd3db9d999b810ca7a9cb3537ca794dd164f940eee14e034583facc5  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/ExpandButton.kt
c74bce80caad5be0042566cb90be695c4f9aee4d992ab966344b585f0e5f3fd6  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/FirebasePongRepository.kt
7cf29d21153a42435b17a5009a1f9c1823be812639d0fe1999e5970f89a631c9  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/GroupMatch.kt
5d413f5e06594dccdf35f52c2e7e8a1ef0025adc0fb1dd9f2b37aa7e23b57215  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/Knockout.kt
20faff32b86da634af584ec81d134187d3cb9379d171a679ea086bce6c8d250b  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/KnockoutBracketView.kt
a06c683dc320e2dc049ffef10cb2c0fcf5b48d1277d8e97c950183958aa4afd2  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/LobbyAudio.kt
9305c1faca41d216793755116ecd230971e23cf4caa5bc6fe478488120ac60e3  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/LobbyEvents.kt
fbbc314fc4097160a361da29d84180b75f3c379ccf74833b78db471c0b318d70  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/MatchLink.kt
0bc051ebbbde053c2420ad3170ff5a5faddc4f1ed3e60486c3c5cd60b02a5f6a  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/MatchText.kt
1558269ac8f2769cbc6cc9710912362a5395b87d39bd20218385700f50e258b3  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/MenuExpansion.kt
5ba15a361ad0228240d11ccb6a8455ea11c0b18e9a61714b48aa513aa5451320  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/MenuScrollView.kt
fb11e7c8107f69796da0c88582ff5c33156577596dc5bb3476f11a9cc45c823f  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/Nicknames.kt
4e3a90aa9347a2099d409d13a2508f05612682254fa691524a07914ff0077519  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/PlayActivity.kt
9729c963acd3e00b624e340d25904eac4a34c4f5ef9bc79f54661a92241e4ed8  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/PongCodec.kt
2035b4a3793920d8e6ee09b3e98cca3eb22367cf236ec4f780c79564d69dd416  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/PongModels.kt
f5f9c92512b0e55d4eca15fc85d15e684d834853120855619b7e65b89041a944  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/PongRepository.kt
4d80ab957732610014301e744c93b7bb00c1e55cfe8498db851677b6305dbe6d  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/PrivateMatchActivity.kt
1124fda7d746f636813f3ed6de8d73fbb1b0589551b98c94954b01ba5803d776  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/RoomBook.kt
```

Resources (texts and converted art) (17 files):

```text
23bd961ecd0545937beacf91435cea97969289da90cf35fdf6bd5555ef8d2680  app/src/main/res/values/strings.xml
2f85b71485c1c53743ba49f7a1d30827c6637a9618980c7bba276fe4f8104bde  app/src/main/res/values-iw/strings.xml
bb61cf126def0c0b2f1af4f34c3171b93770723f694dd42949e25229a97f5085  app/src/main/res/drawable-nodpi/app_icon_cross.webp
9b18d3c8b42cd646453882eea3204b10c42c82bff4fdf308fc202d48530db90e  app/src/main/res/drawable-nodpi/bot_amber.webp
e1d069ebd454d1eeb05263f29660b5d5ab22389291e07635e290718acf6b691a  app/src/main/res/drawable-nodpi/legs_amber.webp
3cb9a966ac623eb356f931b8e94e3e21cb748fcebafd7455f702902f406234f8  app/src/main/res/drawable-nodpi/bot_comet.webp
f8644286e5bb1008ba56904ae800be3e047e8bc41bc8e1978506794febddc644  app/src/main/res/drawable-nodpi/legs_comet.webp
565696812d7edb0cf800bb1a21de35e2ff91841dff37174e6ae69f2753ad55d1  app/src/main/res/drawable-nodpi/bot_flare.webp
bbb9f43e786c1eb0e6a7537467a17eb6e16dde2b4c498f26855567f3a3f57341  app/src/main/res/drawable-nodpi/legs_flare.webp
4f463df6fd2004d56ad60bfe8dfafbddf39854a0ed13dddf9ab4078c3a900d4a  app/src/main/res/drawable-nodpi/bot_gaya.webp
a728d62881fd123254b2eba3a49cd1624347955db8227e19ae69e5820591fcc3  app/src/main/res/drawable-nodpi/legs_gaya.webp
3144cabf603f9b99591cd189bf6f0d0d771feb6bc9cb50de97491dfcb623192a  app/src/main/res/drawable-nodpi/bot_june.webp
0399abc1a296958ad0ad90f4dbe61b79206c72d3e2e1e8dec0565631ef11422b  app/src/main/res/drawable-nodpi/legs_june.webp
ddc80c99c253a16325083883bfd9432dea5f20f2e7c2330ccf2db6242ecae032  app/src/main/res/drawable-nodpi/bot_mia.webp
c51d3848ece1b05fdc14400a85740cf5c6055f943245fe3b40f1a16cd17cd7e9  app/src/main/res/drawable-nodpi/legs_mia.webp
4487ad66fbae95be4469ce91e4c0ac1c2e6b130227667d8416ad2c58cb1ed628  app/src/main/res/drawable-nodpi/bot_moshiko.webp
5b04765ecaadca0d24706096bea9a01ec9ca114e7b0722ee4b4e6c8d48549e50  app/src/main/res/drawable-nodpi/legs_moshiko.webp
```

Unit tests (app/src/test, ported or reviewed) (54 files):

```text
3357b9d3135a69226aa108f0472c1597680a66ac7264d5c8bf4e2a15ee9dcdd5  app/src/test/java/com/appsbybros/minik/monetization/AccessCodesContractTest.java
0a2c7a7df3b90cec6ef6c8dbfea5130d9b702bcfbf227d41b5abf14f6d6fb6f9  app/src/test/java/com/appsbybros/minik/monetization/AccessTokenRulesTest.java
818e643f0fe9d3f12ee385015063a61aec1d9ddba1eedc7c8cbbe8077695f730  app/src/test/java/com/appsbybros/minik/monetization/AdPolicyTest.java
959f8ef51b2622ca38903468a490d59f1ab1c7a5cdb2f36ec1f13646ca7d6f32  app/src/test/java/com/appsbybros/minik/monetization/EntitlementStoreTest.java
45f938e0850f7f8c6a96b81f86d786dca8dcbbf22d69be18e64212518f0580ac  app/src/test/java/com/appsbybros/minik/monetization/LicenseReceiptTest.java
dfbdb53b01e219f5952c01e107f503f389e1e5f0d1a93ebd5effd483bdbef50d  app/src/test/java/com/appsbybros/minik/pingpong/BeginnerAndStrategyTest.kt
bfac0b3965ed78593556448775f4a34b703fbf21a8d0038d2184efec28624c78  app/src/test/java/com/appsbybros/minik/pingpong/BotRosterTest.kt
7ea3267a1db951d2709f99fe8d1b968a7821b66b31d2422c098ffeeef015c215  app/src/test/java/com/appsbybros/minik/pingpong/ClassicFixesTest.kt
350be385df7ff2a1324932eb5bbb879f224e7c7dfb02f5953025865c18332e7e  app/src/test/java/com/appsbybros/minik/pingpong/ClassicTiebreakTest.kt
70e7d70943027ebb2f02908d81362519d9a2fbf2b25d83376fbc598ddda767c5  app/src/test/java/com/appsbybros/minik/pingpong/ControlAndCompletionRegressionTest.kt
283f75e8bbdc0b296bcc710aff9c709cfc9b034243c034d576a4bee59b1628cc  app/src/test/java/com/appsbybros/minik/pingpong/FirebaseActivationTest.kt
a26d4f90ceeb60c2b0dfeb03f0321f91cefc86438e7a022e3f9370a61dee51d1  app/src/test/java/com/appsbybros/minik/pingpong/FriendlyFlowTest.kt
aa9024e861dea092c401bb128edda5eb2ab88a55c7ecb1727536f577955eeadc  app/src/test/java/com/appsbybros/minik/pingpong/GameModeTournamentTest.kt
1b6fa92e5b406e7e03f8711f4ee01e28bfea71856ac31c46429b06163da1abf2  app/src/test/java/com/appsbybros/minik/pingpong/KnockoutTest.kt
bd927c709c9ab96aa453601beef875f57077300311a81988e2826c7b78307cb0  app/src/test/java/com/appsbybros/minik/pingpong/LobbyPauseTest.kt
40bd0310d709dc66fa78156b7cc019e7b1b178d1943aecc058f1dd2302d2dd6a  app/src/test/java/com/appsbybros/minik/pingpong/MinikMotionTest.kt
f151396b23f93535b13e453462bcdc6859e83840d7dc3fd18ae1c1a30daf936a  app/src/test/java/com/appsbybros/minik/pingpong/ModernDifficultyControlTest.kt
f889c4b088a44cf19e8f0e0c4d548ea55a9df0b9837f70ce6c5019e06e913bbb  app/src/test/java/com/appsbybros/minik/pingpong/ModernEngineTest.kt
199506c5ce09639a04708eb58ec095e523bfa76fdbf2024a916eef0725bc76be  app/src/test/java/com/appsbybros/minik/pingpong/ModernFollowupTest.kt
896e7619b83df04278dda1a95656ec57b944b5624a407c3f1f19ad555b0ea202  app/src/test/java/com/appsbybros/minik/pingpong/ModernRefinementTest.kt
d3eb80365ebe7fcbef01ab24dada8e41c88e84a6eae8740b5257712fc1b338cb  app/src/test/java/com/appsbybros/minik/pingpong/ModernTutorialTest.kt
37e47c55c4806df3c691baaff128b5283da8acc6b3c55166dc08230b328c6846  app/src/test/java/com/appsbybros/minik/pingpong/MultiplayerTest.kt
b326eb2c4ac91b49262d7d426f6796cc57870e45d59bee0f013fef2b8cb9f4a5  app/src/test/java/com/appsbybros/minik/pingpong/PeerMatchTest.kt
18072c570aa208dc54e393c283f0e06348929e914c85284165a600b5482d11b6  app/src/test/java/com/appsbybros/minik/pingpong/PointPowerTest.kt
eef15534c5c9a9d05d5edb000c48c6b3cbab8c71f2fd8f18e32588e10c8d5603  app/src/test/java/com/appsbybros/minik/pingpong/PracticeRallyTest.kt
b953ea9a6d1ab27271efd903b4766601eeb933a1289344d2f8e7ea15332e85f0  app/src/test/java/com/appsbybros/minik/pingpong/ProfileAvatarTest.kt
8f0707218249891ea3e8d781d3bb79881aba27be9bf2054ad890782289a80d5a  app/src/test/java/com/appsbybros/minik/pingpong/RoomPolicyTest.kt
de7c430f2701c74c8d6c09ceaa3f3634139943b2d56f52ee742c9ccc43f4d3b2  app/src/test/java/com/appsbybros/minik/pingpong/ServeFlightRegressionTest.kt
0cf449d4c37adf327135f198cfef9cbb31aab047e50c81f03f0c69a5b4ab3892  app/src/test/java/com/appsbybros/minik/pingpong/SpriteSamplingTest.kt
51bcf40f69bec38c50ba3e60b3d8d9e4968c6de88602ba0684b03fa43a91f98c  app/src/test/java/com/appsbybros/minik/pingpong/SwipePhysicsTest.kt
34994da24a112664ab03b4ab435780c28e808e722d8b563ff3c08ac4899d01f2  app/src/test/java/com/appsbybros/minik/pingpong/TournamentUpdateTest.kt
6bfe1129902dc28e6b06e23015bad6d56164d927f74823d01b571634a66155d0  app/src/test/java/com/appsbybros/minik/pingpong/UnifiedFriendlyTest.kt
942abb567bea0108290878b4dbf0a29ee34f1fe219dd3241302e8f6b234130f9  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossAdversarialTest.kt
ba595d6a2f5b6872e643879ffed659a5b2ae1bb6d1383f84779099c1a1f56680  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossBallTest.kt
42062fbf25c34f5c7c5e320988b90f26d92ffe585598f0244fdc44dd7c00ab68  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossBeginnerAimTest.kt
d44429f3e8f70e9f85a3e8296119b332dd01b499127b20265dbdcf1af18343b9  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossControlTest.kt
53d0e46da002a2897dfffc380db7c0a9c0c25c1c42d9f3d347cd992556abab40  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossEngineSupport.kt
c550ee08e122a7df11e23f81b4281f5dc141e532839bd87a3f1841047869033c  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossEventsTest.kt
2722d47e42ddf86171e02200db9301cd9b606c14cf4335462a8326161b382c76  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossExerciseTest.kt
098e28eb89b6eb31a94f4eb65595bd03401fbebd48a755902fc87bbf16e308e4  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossGeometryTest.kt
8272e2fac76efd58df71850aed6563d06b2e4e2d18c304faffe88929c1578fd8  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossHouseTest.kt
95aaa23ba1181b22aa7e74f105849fe801339d2c28da6e3f8ea7147d58c8ff7d  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossLinkTest.kt
c021b9838c671a06f2936fbda3785e968d86b7e362c465a1d895087a115d7484  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossMatchTest.kt
3b995f5267f8a2b1813718ddea2132b239a2b3a901adfb6c986c8222a639a353  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossModesTest.kt
e7efabf7323de7155f923df0eb7fac64941eb7f52ee2c289ecd339cdbc76e992  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossNetworkTest.kt
76865cedc6b81b0a4888ab3ca7a7b83be30d28bff86eaf0f62fbf7075b02ec4c  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossRallyTest.kt
06e2012004d02e00bd6fc660d162e6834061ff414a81b055cbe357e73a014944  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossRefereeTest.kt
378d638be22a47dd0d37b789215cac2005b83b3c65e43839c8285592ffc605c4  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossShotsTest.kt
bdbd279ef7eaf6ba02f8ebaa62e669d7a059000caa0db61fde9203b0f55713e9  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossTestSupport.kt
279934726be9876962d37b6a8ef63c2ab56a8461b4e8cf7e9cb054fe4b5b8949  app/src/test/java/com/appsbybros/minik/pingpong/multiplayer/GroupMatchAdversarialTest.kt
0c91635db7026b8429c0a3aa7d18409d212ad4452780ae98028c37b43258d265  app/src/test/java/com/appsbybros/minik/pingpong/multiplayer/GroupMatchModelTest.kt
2e0c7e39588e6e98a100a71d1f7d08f126d68112fc3b141a1557282d9ceffe2d  app/src/test/java/com/appsbybros/minik/pingpong/multiplayer/GroupTournamentTest.kt
8ede08976a4cf47d96209ca5ea89bef51f72c834eadd9598c01e26eef8ffd6e6  app/src/test/java/com/appsbybros/minik/pingpong/multiplayer/MatchTextTest.kt
0304ce7735d4f4f4ee4723126eb245ccd12e26a6f6e22dc8534ff3db93164156  app/src/test/java/org/json/AndroidJsonForTests.kt
```

Firebase rules, tests and configuration (9 files):

```text
6020a7fc40899509f4709d531f5b298d8cd1a63157705a133440d0270facda97  firebase/README.md
fd4865faf4b97c2be6ca062ff9901fab59609579a2cbf473a9cd973b3bc8e9f8  firebase/crosspong.rules.fragment.json
3d44d94a6cad6b9364fd76f6e1b21016e857dd96b54f9be303a0279041d4798f  firebase/package.json
c62426d2d972d7988d9383b0b63ae9506d45acef8733859daf528ca8a54b2199  firebase/tests/configuration.test.cjs
e0fcfd485ad48079b395d62f6bed296535e4a60a864a28e540b3209d734ef8df  firebase/tests/crosspong.test.cjs
911482b5e9da99ce3aa4a21a37b50a45f506a31bfc2785ee605c97a936ea9732  firebase/tests/pingpong-regression.test.cjs
eb60d8c525bf443018dff3c1a420b3646dc323f06cd4240aea6d8c70fa48750b  firebase-setup/current-database-rules.json
4fa06ac66c97ed98a97d949213c19b241f7bc5d366a401fbeec0fc42078cb3f3  firebase-setup/merged-database-rules.json
67ee6a435147a9802fce092951a1a5a60934c1ea77536fd34f6d833009371131  firebase.emulator.json
```

Design reference (1 files):

```text
89d04d8c3d903b37a964bd00ef26a515c9250b8695053006f6762ea09a2f9c7c  docs/CROSS_DESIGN.md
```

Added since `828c6fc`: the six languages and their tests (used by the 2026-10-04 and 2026-10-07 updates) (7 files):

```text
78fce8bd16b0b9f1c2faeffff647ef9007cc2eee37044d13595ce12f7031b79e  app/src/main/java/com/appsbybros/minik/localization/AppText.kt
4bb329f4df53ed0283dffb53d3b2f645990b6f3a27ddfa7716b7afce1bcd9030  app/src/main/res/values-ar/strings.xml
18383d07348fa27fc1a4eb5ed53cd67a480ce1cbf80ae24b6096b663df513662  app/src/main/res/values-es/strings.xml
62bb4dff10e41742ce4e35d889d633bc08b8dc52f40cdcd80356c8edd621ff2c  app/src/main/res/values-hi/strings.xml
dcbbc1c3d0c3b7f20a224f7157ac29d2f71d0fbb514d18319161e5bea8fb7d43  app/src/main/res/values-nl/strings.xml
c0ecbdbe6f8fe561f99475d8e1b5f704cbfeaa0aaa9abac562a5e41afb07e816  app/src/test/java/com/appsbybros/minik/localization/LanguageTest.kt
1eb8a56ec0b81aebe996dc239fb4ea20f1a74c0fa71bc78ebc33e13556ab3f30  app/src/androidTest/java/com/appsbybros/minik/pingpong/LanguageDeviceTest.kt
```

Reviewed and not ported (Android purchases and build, and the QA notes that describe the 2026-10-06 changes) (3 files):

```text
2c163794345244e6bcc34677d0bf8c148da219c0cd9b31c99639e7125b7d984c  app/src/main/java/com/appsbybros/minik/monetization/MonetizationActivity.java
354d30f1df807d6e72ceb32cf724642ee4c228b22a68708b587ae8c8c10eb2a9  app/build.gradle.kts
9c48a800a781bb966749a054481e6560552d20294d41f0f94f345d273f16df97  docs/qa-2026-10-06.md
```

Added since `1908719`: Kotlin sources of team play, reception assistance, the journey, online team rooms, the pose atlas and the menus (2026-10-13 sync) (17 files):

```text
c61f588ff5321b3f2de7168cb51e16a8716b8f0ec186811b5a60bbe0ba2b6f9b  app/src/main/java/com/appsbybros/minik/pingpong/cross/CrossTeams.kt
859906d9130809ab5ef698b8ee4a75335164f69b79fd8b4cef2d3ae125276113  app/src/main/java/com/appsbybros/minik/pingpong/cross/CrossTeamRoom.kt
4c871645dc170426d707032bd92187f3cf65841ea657ebca5ff5dab938e1cf8c  app/src/main/java/com/appsbybros/minik/pingpong/cross/CrossOnlineTeamsActivity.kt
afb9bd8c2ad1e4c8729c6bac38aa02eda710dbc66446232fbfc025fba94e38c1  app/src/main/java/com/appsbybros/minik/pingpong/cross/CrossPractice.kt
bcddf7fd0bdc9eaa06d28d08c864316f0ae810f596c4b93f415035294271354c  app/src/main/java/com/appsbybros/minik/pingpong/cross/CrossJourney.kt
47ba5530da3a4bab7727b6278ea79fc6a42408029c5bc48f42268eeb18c45d77  app/src/main/java/com/appsbybros/minik/pingpong/cross/CrossJourneyActivity.kt
9ba2733cabd83de432c4a82be580a49fe4a7837256c85f08bfb4a9f049704abe  app/src/main/java/com/appsbybros/minik/pingpong/ReceptionAssist.kt
4ec3a3d4efae8e6c4ef49b13464a9e8874673351bf55ee56eefc210675e9e00c  app/src/main/java/com/appsbybros/minik/pingpong/ReceptionCamera.kt
7bbb147f2e0b0efd423184587b8921e8c9bb8c879d2f7036ecd55b22ba771da4  app/src/main/java/com/appsbybros/minik/pingpong/TeamLineup.kt
530efdf254dd46f0d1ba28c312580a3d8c4c81eddf8bd743e606fc2dc4b2eead  app/src/main/java/com/appsbybros/minik/pingpong/TeamLobbyCards.kt
1e310e753da895eb76bd2bd32c5ec8067185c91849ae9963148e607a4ff7be38  app/src/main/java/com/appsbybros/minik/pingpong/TeamPlayerIdentity.kt
7888cf435f57e8f3d5135a1dc4f0025fc4061e203da6d5e7662e024020dc4944  app/src/main/java/com/appsbybros/minik/pingpong/TeamVictoryView.kt
c7cb5c5d7b9e746ba089b46cfcd60938084db28ae22812cece850a64430c4d96  app/src/main/java/com/appsbybros/minik/pingpong/PongPlayerAtlas.kt
67684b07b830d98fdd4f2806de0c4bfea5210e320e0ace6b66c35a95d0c320d9  app/src/main/java/com/appsbybros/minik/pingpong/MatchSceneLayout.kt
7134b64f53f6583b4e635e6641f4ab243bc38b6c110c9f3b902b0f18234e00e5  app/src/main/java/com/appsbybros/minik/pingpong/PongMenuMusic.kt
1f18b6e83c7151ba07eab66b4d9990482fb71fbeaa25c5423bcc869d089f7354  app/src/main/java/com/appsbybros/minik/pingpong/ReadingPanel.kt
a612381b5fc6d679f03b87773a70e1b471f4e4b4604f5edcb94aaa6392edc149  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/MenuMoreFrame.kt
```

Added since `1908719`: texts, art and sound (2026-10-13 sync; the PNG sheets are copied as they are, the webp and OGG files converted) (47 files):

```text
58a9ff2ecf8e42f76c784aba5fba7bfa1db58883afcf63a9958c578f507bce83  app/src/main/res/values/journey.xml
6f01d1cbeea8f2ab24bdce84e7116a882244df24e7d1a11a022f785c488895f1  app/src/main/res/values-iw/journey.xml
af0bd24eed1b55296e27b86b4995ff0ab7ace178ef469fca9f43fffb420112a6  app/src/main/res/values-ar/journey.xml
9c2df7652815e63e930900712eb34802c10d53500c9d978cd4d077537bf2f783  app/src/main/res/values-es/journey.xml
527eebe33f86df6d043ed61bc62e4fea929d5d1d12f9cebd26f267a00bc4d469  app/src/main/res/values-hi/journey.xml
65f206fb094df4a5aad1eb363f0bf69c22008beb9eb629c18395f1bd389ca0fa  app/src/main/res/values-nl/journey.xml
8dbc200a989971afd225b170dbaec79bf2ca6519de654253282d97f3bb7aef8f  app/src/main/assets/pong-poses/atlas.json
3c1f5ecad2c94d9f3d64f95b1f4bdb3d79480f64745f6c15e537ff2a82f47713  app/src/main/assets/pong-poses/amber.png
cc8472c12ab4041e455a14395b5ba1f58211f63be05daea53d640dcc43153409  app/src/main/assets/pong-poses/amber-walk.png
664985915ce4f036fcac233db6a08c2a7643e16cd6e14ed2726038804041d3ef  app/src/main/assets/pong-poses/coach67.png
bd71241194b35eb3531175d3f8fe2a65bc93a27760d54b0a750c7490a9dc0195  app/src/main/assets/pong-poses/coach67-walk.png
479cd285a1cb3fb5274a92e2ed2e746af43033ca413cb5247ca11e8591e1def2  app/src/main/assets/pong-poses/comet.png
8fd338c73bedf2870514f627fbbae6a7712f1c70273a807a61bc4d8930cabaae  app/src/main/assets/pong-poses/comet-walk.png
1ecf9039af7f5e1fe8c3c8b030d83d4122b46c54be50e4fa673cd41268672f9c  app/src/main/assets/pong-poses/flare.png
2da698edc69452f216faa687f960111100bf8833f8def5e9f160bc06b3d580df  app/src/main/assets/pong-poses/flare-walk.png
d3cf14ffd50a682a4d7fa4a6f1757974ac91d979d0bd3fd147afe9cd2c057acb  app/src/main/assets/pong-poses/gaya.png
3fa96c08832691db7ca28976b06c54c6d78c13e83efec4f96f03cd72755e25dd  app/src/main/assets/pong-poses/gaya-walk.png
e5612bd220dec893be1d8968f860cc6232233166e9fcdc0db225c5a867fe8b9c  app/src/main/assets/pong-poses/june.png
f9d1888c987afce996a2e7ba96f574ffddf5a8b0f3bea9f4d3d98409d209091a  app/src/main/assets/pong-poses/june-walk.png
eb4b263f6c965055d6e23c9b4c0236dc756610624a2a2fd4d2aaa51293996027  app/src/main/assets/pong-poses/kyra.png
8f43bf98faa519a9c27bc04af584ae63da2f09d313e377c6caf2cb3dcb0f7dc1  app/src/main/assets/pong-poses/kyra-walk.png
892d56c0e544cef40919683038386485977f7f1b85e98d3922a30827be80f4be  app/src/main/assets/pong-poses/mia.png
5b5d1d6af97a454d188f23906ae38fbff5bbe3e2a694050beabdd1b4997eabc5  app/src/main/assets/pong-poses/mia-walk.png
4a1f00c99ef332ea160d7edba7cfda133d8711b4f3d174f554e181fc3d508e9f  app/src/main/assets/pong-poses/minik.png
ac4a2fbff3723b32dd5dd0c956859319c6335802dcd3d831ec0d30f87d6ed0be  app/src/main/assets/pong-poses/minik-walk.png
7948a2f53a70c8b73d94f28a21173ff403ea55586cc73c8b56b8f897aedd3636  app/src/main/assets/pong-poses/miniko.png
f69ae0daaa57eb3a91c82961017d327987879227525a9a623842f479af83bd65  app/src/main/assets/pong-poses/miniko-walk.png
0420f1eda907bfd73fd9f03c055c0201feca4f52ca6f052ffd23279d16b85bc7  app/src/main/assets/pong-poses/moshiko.png
724ea3960799cd506775e84e905c6d2fe12e51159dbc597854ac8d2e8a3a41f2  app/src/main/assets/pong-poses/moshiko-walk.png
61491ac078dc9cec53fff05302a57a56ba9aba23a53fc6384af5a14a4f722daf  app/src/main/assets/team-celebration/amber.webp
14de8efc2a86d0ebed5d089dad7b0822efc4789b7210470ff6fbb8471e762cd7  app/src/main/assets/team-celebration/coach67.webp
cdff140135fcd524b7d6bc839df9e2cbe076468ed1e6517ee55f7cb7c59bd3a5  app/src/main/assets/team-celebration/comet.webp
4fca70b0916e0bddd3caee74ee5f34810e52ce91422806d9699b9eff24d2fd7c  app/src/main/assets/team-celebration/flare.webp
11807974e2e073833ccf67ad77a8ff4eb00b5176f0d1a2ab9e1694c4c3fa6dbd  app/src/main/assets/team-celebration/gaya.webp
23fbe421ea99f8b577fe7b5cfede2d5875b98bcace6259de7d2f041ee9b317c0  app/src/main/assets/team-celebration/june.webp
2c0619fc335a03a1143e4baec109ea3da1f273784fcf24602b68bd2096e0b262  app/src/main/assets/team-celebration/kyra.webp
cd44de786acae57914bb68b10c64fe1d15086c138d3dcba8d4332abb2424b043  app/src/main/assets/team-celebration/mia.webp
ab316eabae11ed208d69a86e8a3f40f76b96026871d40822b8fcd2d0098ae811  app/src/main/assets/team-celebration/minik.webp
9ddb214fc04ceba95926ef5a583682ab8dc6a13171d4c5b68c57ec45f97857d9  app/src/main/assets/team-celebration/miniko.webp
10e800ea877fcf85e9b70acb16a72d021ad0c00565943c1cd941cadf76f0cfc6  app/src/main/assets/team-celebration/moshiko.webp
1ec45c8455648af3e065a04f3d07433a307cf15a7112795e9e4be5c29241d12a  app/src/main/res/drawable-nodpi/cross_sunset_landscape.jpg
ff9fd477a8ea1244275f5b7944df3597a8abc50dbb38b347fd50f6737c77e750  app/src/main/res/drawable-nodpi/cross_sunset_portrait.jpg
2c61cde99ba7c12113f7cf5c6ade02aac9de8e9ecd3ac10e8fd889a9cac57f63  app/src/main/res/drawable-nodpi/multiplayer_menu_landscape.png
6ed964a08e423029fec6bdb00fbb2c549cd3eea558e5cf5b5627b18898be5338  app/src/main/res/drawable-nodpi/multiplayer_menu_portrait.png
b5c1826926860dd2398f4884fad3b1732473e1c800dcf9aa2257ab4d212888ed  app/src/main/res/drawable-nodpi/tournament_remove.webp
96b0411395bdde1414b17996319f2eb603c4f7b34dd57cd23ff488636e5b4495  app/src/main/res/raw/pong_menu_remix.ogg
92b58e57217b3a793d21805e51adad4d8dbada6ab7530c85494c2d502a9ca420  play-store/current/source/sunset-logo/master.png
```

Added since `1908719`: unit tests (2026-10-13 sync, ported) (7 files):

```text
bb32734e95113b97f18b556b377571b12c87aab1cee228d76c87898c211c41fa  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossTeamTest.kt
4f95f2197e90b98a02f6ab271b9044db7425b2e5d853f8ecbe001e50426e3edc  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossNetworkTeamsTest.kt
91ecd036302f753bf74abf63869e864e7616965d64decbfb4b237da78723b63a  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossPracticeTest.kt
b5587170669d187637b2022754943a5236473aa51fd162226adb8d77b80387f1  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossSetGestureRegressionTest.kt
659c5256f76761753ce254be236a7580dc71404ac0ac9bcc9ac9b7ea5fcee6a1  app/src/test/java/com/appsbybros/minik/pingpong/cross/CrossTeamPaceRegressionTest.kt
2d348a61ecd97d3a376155938ddf512b6a48026ca3f61b1e3c00bc76aeb855a2  app/src/test/java/com/appsbybros/minik/pingpong/ReceptionAssistTest.kt
52e606253fe53848c44c2646190d3345115889dacecbafbda8e2d23b3a5bdac7  app/src/test/java/com/appsbybros/minik/pingpong/TeamLineupTest.kt
```

Added since `1908719`: Firebase team-room rules and tests (2026-10-13 sync; `lineup.rules.test.cjs` reviewed, not mirrored) (4 files):

```text
deebc153200097b2dda4145019c3d44269318495d1c836924d706e0716229535  firebase/cross-team.rules.json
a25de0a2742c3aa820a28e3cd5e64de00cae80c0118f62b5a4b77647feb43204  firebase/tests/cross-teams.test.cjs
1926e12b0287d7ac2c7e5f1ee801bb385a27deec6ed1fd2972a1b673ddbdc4b9  firebase/tests/room-identities.test.cjs
1cc2f5642212e4d43478504694184a004918b48e5512c7cef66050490560b263  firebase/tests/lineup.rules.test.cjs
```

Added or changed since `1908719`, reviewed and not ported (unused art code, Android ads and family messages, Android build) (2026-10-13 sync) (7 files):

```text
7cb19b114fcd93a8964db88630c5b8797ba245090281573ff2211728d57870ce  app/src/main/java/com/appsbybros/minik/pingpong/CourtPlayerArt.kt
1b17652f5dac7d4d72e08aa3ffbeefdc40ad7728ababbc3cddcadc860e2e451f  app/src/main/java/com/appsbybros/minik/pingpong/WholePlayerArt.kt
41aa34cfbbbef03fee9a4a61b273a4e69df6f4a9175016e05668dfa97df62f2b  app/src/main/java/com/appsbybros/minik/pingpong/JourneyCelebration.kt
dc7d18cefe6bde7f0752eefc0ceb8d5ca341093c151fd2304804b63562a4715b  app/src/main/java/com/appsbybros/minik/monetization/AdCoordinator.java
dcda02812781b23fa8f4c7be866432194826e2b2d766bfbe6ab19bd676408e4a  app/src/main/AndroidManifest.xml
d550e6adda3d28d21c5844cfe9781a01b0f29dbadf30ecf6cc6c95cd8ff4391d  firebase/generate-rules.cjs
7ae4c84dd32031070ff5e81a373f376b07fea23723c472159be2335537413796  BUILD_STATUS.md
```

## Update 2026-10-04: six languages (Android working tree on 828c6fc)

Source: the uncommitted working tree of `C:\Projects\MinikCrossPong` on top of `828c6fc` (the delivered revision in its
`delivery/revision-2026-10-04/`). It adds Spanish, Arabic, Hindi and Dutch to English and Hebrew with one catalog,
`localization/AppText.kt`, and passes the game's English/Hebrew text pairs through it. Android's `firebase/` did not change, so
`Tests/MultiPongFirebase/` did not change either. The Android repository was only read.

### What changed in this repository (uncommitted)

| Area | Files |
| --- | --- |
| New | `MultiPong/MPText.swift` (Android `AppText`: language rules and lookup), `MultiPong/MPTextCatalog.swift` (its 820 rows, generated from `AppText.kt`), `Tests/MultiPongTests/LanguageTests.swift` |
| Edited | `MultiPong/CrossText.swift`, `CrossTutorial.swift`, `MPKnockout.swift`, `MPKnockoutBracketView.swift`, `MPGroupMatch.swift`, `MPMultiplayerModels.swift`, `MPController.swift`, `ModernPongView.swift`, `MPTutorial.swift` |
| Project | `project.yml`: only the `CFBundleLocalizations` of `MinikMultiPingPong`, now `[en, he, ar, es, hi, nl]` |
| Audit | `Scripts/audit-multi-pong.py` (see "Checks run" below) |
| This document | this section and three pointers above |

The edited and new files have LF line endings. Git's index already stores LF for them, so the line endings add no diff.
`Sources/**`, other targets and the Firebase mirror were not touched. No `xcodegen` change is needed beyond the one plist value.

### Language rules (Android `LocalizedActivity` and `AppText`)

- **Device language.** The app language is the primary device language (`Locale.preferredLanguages.first`), read again whenever
  `ModernPongView` is created, as Android reads it in every activity. Only the language part counts ("es-MX" is Spanish; iOS
  "_" separators are accepted too), "iw" is Hebrew, and any language other than the six is English.
- **No in-app choice**, as on Android. Android's only override is a debug-build extra for its screenshot test, which is not
  ported. On iOS a language can be tried with the Xcode scheme's App Language or with the app's own Language row in the
  Settings app, which iOS reports as the first preferred language.
- **Right to left.** Hebrew and Arabic lay out right to left: the whole screen, its sheets and its alert (the layout
  environment is now the last modifier of `ModernPongView.body`), the back arrow, and the knockout bracket's cards, titles and
  player rows. As on Android, the bracket's column order (and its scroll anchor) stays mirrored for Hebrew only.
- **Host locale.** The shared `Sources/RootView` gives this app only an English or Hebrew `\.locale` and layout direction.
  `ModernPongView` no longer reads `\.locale`; it sets its own direction.
- **Names never translate.** House-player names, nicknames, stored names and network values never pass through the catalog:
  Hebrew names in Hebrew, English names in every other language, as on Android.

### How a text is looked up (`MPText.t(en, he, hebrew)`, Android `AppText.t`)

1. `hebrew` true: the Hebrew text.
2. English (or Hebrew with `hebrew` false): the English text.
3. Spanish, Arabic, Hindi, Dutch: the catalog row with exactly this English text.
4. Else the first `{0}` key that matches the whole text (longest key first, catalog order between equal lengths, each `{n}`
   as short as possible); its `{n}` are filled with the matched names and numbers.
5. Else the row of the text without its leading and trailing spaces, keeping those spaces.
6. Else a " · " prefix is kept and the rest looked up.
7. Else the English text.

`MPText.t(en)` (Android `AppText.t(en)`) uses the English text as the Hebrew one. The Swift ports call it exactly where the
Android working tree does, including the two double lookups: the whole rally outcome in `CrossText.outcome`, and the guide's
control line in `CrossTutorial.card` (its control name is translated before the line is looked up).

### Android → iOS mapping (working tree)

| Android (working tree on 828c6fc) | iOS |
| --- | --- |
| `localization/AppText.kt` | `MPText.swift` (`normalize`, `configure`, `configureFromDevice`, `language`, `rtl`, `t`, `translated`, `keys`; `MPTextTemplate` for the `{n}` keys) and `MPTextCatalog.swift` (the rows in Android order; regenerate with `python3 Scripts/audit-multi-pong.py --android <MinikCrossPong> --write-catalog`) |
| `res/values-ar`, `values-es`, `values-hi`, `values-nl` `strings.xml` | Not copied. Each of their 103 strings except four (the app name "Multi Ping Pong", "Minik" and two format-only strings, identical in every language) is a catalog row with the same translation in all four languages, so iOS shows them through `MPText`. This was checked string by string. Since `1908719` one Dutch string differs from its catalog row; the 2026-10-07 update ports it and makes this check part of the audit. |
| `LocalizedActivity.kt` (language, RTL, Back) | `ModernPongView.init` (`MPText.configureFromDevice()`), `he`, `t`, `backButton` and the layout direction; `MPController.hebrew` and `MPController.text` |
| `GuideDialog.kt` (RTL) | The guide card and the sheets read in the screen's direction |
| `BotPicker.kt`, `HousePlayerPicker.kt` | `ModernPongView.housePicker`, `carousel` and `statsLine` |
| `ModernActivity.kt` | Not applicable. Its three changed texts ("Match finished", "Opponent: ", "Select") belong to Android's local classic screen, which this port does not have. The Simple experience's own texts go through the same `t`. |
| `cross/CrossActivity.kt`, `multiplayer/PlayActivity.kt`, `PrivateMatchActivity.kt` (`tr`) | `ModernPongView.t` (also used by `ModernPongRooms.swift`) and `MPController.text` |
| `PlayActivity.avatarNames` | `ModernPongView.avatarName`: the six profile icons get these spoken names (they had no accessibility name on iOS) |
| `PlayActivity` share text (`AppText.rtl` gravity) | `ModernPongRooms.friendlyRoom`: leading alignment, which is right in Hebrew and Arabic |
| `cross/CrossText.kt` | `CrossText.swift` |
| `cross/CrossTutorial.kt` | `CrossTutorial.swift` (`controlName`, `side`, the control line, "Return the ball to …") |
| `multiplayer/Knockout.kt`, `CompletionText.kt`, `ControlChoice.kt`, `MatchText.kt` | `MPKnockout.swift` (`MPKnockout`, `MPCompletionText`, `MPControlChoice`, `MPMatchText.duelTitle`); `TournamentFormat.title` is `MPTournamentFormat.title` in `MPMultiplayerModels.swift`. `advanceText` stays English/Hebrew, as on Android. |
| `multiplayer/GroupMatch.kt` | `MPGroupMatch.swift` (`MPGroupTournament.stage`) |
| `multiplayer/PongModels.kt` | `MPMultiplayerModels.swift` (`MPGameMode.title`, `explanation`) |
| `multiplayer/KnockoutBracketView.kt` | `MPKnockoutBracketView.swift` |
| `test/.../localization/LanguageTest.kt` | `LanguageTests.swift` |
| `androidTest/.../LanguageDeviceTest.kt` | `LanguageTests.testSixDeviceLanguagesResolveTextsAndDirection` (in part) |
| `LocalizedActivity.visualQA`, the QA guards in `PlayActivity` | Not ported: Android device-QA tooling |
| `monetization/MonetizationActivity.java`, `app/build.gradle.kts` | Not ported: Android purchases and build (version code, test runner, a Fragment constraint). This app has no ads or purchases. |

### Decisions and remaining differences

- **House-player stats line.** Android's picker writes "Power 9  •  Forehand …" with "•", which never matches the catalog key
  "Power {0}  ·  Forehand {1}  ·  Backhand {2}  ·  Serve {3}", so Android shows it in English in the four new languages. iOS writes
  the English line in the key's form, so Android's catalog translation shows. The Hebrew line is unchanged.
- **Players steppers.** "Players: n" and "Standings points per win (pairs): n" are now `t("Players") + ": n"` and
  `t("Standings points per win (pairs)") + ": n"`, the labels of Android's selectors, which are catalog keys. The English and
  Hebrew output is unchanged.
- **Texts without a catalog row stay English** in the four new languages, exactly as on Android. Among the ported texts these
  are: "Elimination", "Winner takes all" and their explanations, "Bye · advances", "Playing now", "🏆 Winner!", "Who will win?",
  the bracket's spoken description, "Previous nickname", "Next nickname", the advance messages ("You reached the final!", …,
  which Android does not pass through `AppText`), and the two connection messages of a cross match.
- **iOS-only texts** have no Android counterpart and therefore no translation; none was invented: the header captions
  "Tournament match", "Ping Pong" and "Match result", "OK" (Android uses the system's OK), "Retry online connection", "Loading",
  "Expanded", "Collapsed", and the classic screens of the Simple experience (not reachable in this app). "Multi Ping Pong" (the
  app name) stays English, as in Android's four new `strings.xml`.
- **Digits** stay Western, as Android's catalog inserts them; `\.locale` is not changed.
- **Unit tests and the simulator language.** `LanguageTests` resets the language to English after each test, like Kotlin's
  `@After`. The other suites expect English for `hebrew: false`, as before, so they need a simulator whose first language is
  English (or Hebrew, or another language outside the six), which is the default.

### Tests

`Tests/MultiPongTests/LanguageTests.swift`, 9 methods; each names its Kotlin original:

| Kotlin | Swift |
| --- | --- |
| `LanguageTest.deviceTagsMapToSupportedLanguages`, `allFourLanguagesHaveCompleteCatalogColumns`, `rtlAndExistingHebrewArePreserved`, `placeholdersPreservePrivateNamesAndNumbers` | the same names, 4/4 |
| `LanguageDeviceTest.sixDeviceLanguagesResolveResourcesAndRenderCrossCourt` (instrumentation) | `testSixDeviceLanguagesResolveTextsAndDirection`: language, direction and a translated resource text for all six; the activity launches and screenshots are not ported |
| — (iOS) | `testLanguagesFollowAndroid`, `testPaddingAndSuffixKeepTheirSpacing`, `testGameTextsUseTheCatalog`, `testCrossTourTextsUseTheCatalog` |

Their expected texts were computed by replaying the `MPText` lookup in Python over the generated catalog and compared with the
Swift sources. Nothing has been compiled or run: this Windows machine has no Swift toolchain.

### Checks run

- `python3 Scripts/audit-multi-pong.py --android C:/Projects/MinikCrossPong`: OK. Besides the earlier checks it now
  - re-hashes the working-tree files of this update (the 138 committed blobs at `828c6fc` still matched; since the 2026-10-07
    update the audit checks these files as committed blobs of `1908719`);
  - compares `MPTextCatalog.swift` with Android's `AppText.kt` row by row (820 rows) and checks the hash it names;
  - checks every catalog row (four non-blank columns, no duplicate key, no placeholder missing from its key);
  - checks that `MPText.languages`, `MPText.columns` and the target's `CFBundleLocalizations` agree.
- Every `MultiPong/*.swift` and `Tests/MultiPongTests/*.swift` file parses without errors with tree-sitter-swift 0.7.4.
- A scan of every `t(…)`, `tr(…)`, `text(…)` and `MPText.t(…)` English literal against the catalog gave the lists in "Decisions"
  above; all the other ported texts have a row.
- Line-by-line compile review of every changed Swift file against the declarations it uses.

### Android files used (2026-10-04)

This update read 26 files of the Android working tree on `828c6fc`. It ported or used 24 of them, and reviewed
`MonetizationActivity.java` and `app/build.gradle.kts` without porting them (Android-only). Android committed all 26 in
`1908719`. 24 of them are byte for byte the files ported here: this was checked against the on-disk hashes that this section
listed, and against the copies that Android's QA pass of 2026-10-06 kept of its files before its changes. The other two,
`LanguageDeviceTest.kt` and `values-nl/strings.xml`, changed after this update; the 2026-10-07 update below ports them. The
blob hashes of all 26 at `1908719` are in "SHA-256 of the Android files used" above. The on-disk hashes of the files that the
audit reads from the working tree are at the end of the 2026-10-07 update.

## Update 2026-10-07: Android 1908719

Source: `C:\Projects\MinikCrossPong` at commit `190871983cb5b72715604d1e48b6dd6bb6c8a22f` ("Polish multilingual dialogs and
player tags; refresh store assets", 2026-10-06). Its working tree is clean apart from untracked delivery and store folders.

`git diff 828c6fc..1908719` touches 138 files:

- the six languages of the 2026-10-04 update, now committed;
- the device, language and large-window QA pass of 2026-10-06 (`docs/qa-2026-10-06.md`);
- store assets, privacy pages, QA evidence and build files.

Compared with the working tree that the 2026-10-04 update ported, only three app files differ: `cross/CrossCourt.kt`,
`res/values-nl/strings.xml` and the instrumentation test `LanguageDeviceTest.kt`. Two sources confirm this: the hashes
recorded on 2026-10-04, and the QA pass's backup of its files before its changes
(`C:\Projects\MinikProWorkspace\store-work\expanded-qa\before-changes\MinikCrossPong`). `AppText.kt` and Android's
`firebase/` did not change, so the catalog rows and `Tests/MultiPongFirebase/` did not change either. The Android repositories
were only read.

### Android → iOS mapping (1908719)

| Android | iOS |
| --- | --- |
| `cross/CrossCourt.kt` `drawTags` (player tags): the badge of every other player is anchored on that player's sprite: its stand line beyond the arm end, at the racket's sideways position, raised by 0.84 of the character's height plus 8 dp. It now sits above the head. Before, a separate world-height projection could put it over the face on tall screens. | `CrossScene.renderTags`, statement by statement (Android dp are iOS points). The viewer's own badge is unchanged. |
| `res/values-nl/strings.xml` `new_match` (dialogs): "Toepassen en nieuw spel starten" was shortened to "Nieuw spel starten", so that Cancel stays visible in the cross settings dialog. `AppText.kt` keeps the longer text, but Android shows this button through `getString(R.string.new_match)`. | `MPText.resourceTexts` lists the Android `strings.xml` texts that differ from the catalog row of their English text; this is the only one. `MPText.resource` (Android `getString`) shows it, in the apply action of the settings sheet (`ModernPongRooms.crossSettings`). `MPText.t` keeps the catalog text, as `AppText.t` does. |
| `androidTest/.../LanguageDeviceTest.kt`: in each of the six languages, both actions of the cross settings dialog must be fully visible | `LanguageTests.testSixLanguagesSettingsActionsUseAndroidResources`: in all six languages, the two action texts are Android's resource texts. The iOS sheet stacks its actions at full width, so there is no layout assertion to port. |
| `localization/AppText.kt` (unchanged) | `MPTextCatalog.swift`, regenerated with `--write-catalog`: the same 820 rows. Only its header changed; it now names `1908719`. |
| The other 23 files of the 2026-10-04 update (unchanged since then) | No change; `MonetizationActivity.java` and `app/build.gradle.kts` stay unported |
| `.gitignore`, `play-store/**`, `website/**`, `docs/qa-2026-10-06-results.json` | Not ported: repository settings, store assets, privacy pages and QA evidence |

### What changed in this repository (uncommitted)

| Area | Files |
| --- | --- |
| Court | `MultiPong/CrossScene.swift` (`renderTags`; the header comment now names `1908719`) |
| Texts | `MultiPong/MPText.swift` (`resourceTexts`, `resource`; header comment), `MultiPong/ModernPongRooms.swift` (the apply action of the settings sheet), `MultiPong/MPTextCatalog.swift` (regenerated, header only) |
| Tests | `Tests/MultiPongTests/LanguageTests.swift`: one new method (10 methods now) and the header comment |
| Audit | `Scripts/audit-multi-pong.py` (see below) |
| This document | this section, the hash lists of "SHA-256 of the Android files used", the 2026-10-04 file list and the pointers above |

`Sources/**`, other targets, `project.yml` and the Firebase mirror were not touched. Every edited file keeps its line endings.

### Audit

- `ANDROID_COMMIT` is now `190871983cb5b72715604d1e48b6dd6bb6c8a22f`, so `--android` checks the committed hashes above at
  `1908719`.
- New: `MPText.resourceTexts` must name catalog keys and catalog languages, and must really differ from the catalog. Its texts
  must be shown through `MPText.resource`, never through `t()`.
- New, with `--android`: every string of the working tree's `values-es`, `-ar`, `-hi` and `-nl` `strings.xml` is compared with
  the text that `MPText` shows for its English text in that language: the catalog row, or `MPText.resourceTexts`. That is 396
  strings. The four strings that are not catalog rows (`app_name`, `minik`, `guide_progress`, `guide_live`) must equal their
  English text. This automates the 2026-10-04 "string by string" check, and it is how the Dutch change was found.

### Checks run

- `python Scripts/audit-multi-pong.py`: OK.
- `python Scripts/audit-multi-pong.py --android C:/Projects/MinikCrossPong`: OK. All 148 committed hashes at `1908719` and
  the 6 working-tree hashes match. The 820 catalog rows and the 396 `strings.xml` texts agree.
- Every `MultiPong/*.swift` and `Tests/MultiPongTests/*.swift` file (68) parses without errors with tree-sitter-swift 0.7.3.
  The audit's bracket balance check passes for all of them.
- Line-by-line compile review of the changed Swift against the declarations it uses (`CrossGeometry.toLocal`, `fromLocal`,
  `home`, `CrossEngine.racket`, `CrossScene.screen`, `sizeAt`, `stand`, `character`, `Double.mpClamp`, `ModernPongView.he`,
  `action(_:color:_:)`).
- The new test's expected texts were taken from Android's `strings.xml` files, and the `MPText` lookup was replayed in Python
  over the catalog.

Nothing has been compiled or run: this Windows machine has no Swift toolchain.

### Android working-tree files used (2026-10-07)

The on-disk hashes that this update recorded were replaced by the 2026-10-13 sync: they are at the end of this document.

## SHA-256 of the Android working-tree files used (2026-10-13)

The files that the audit reads from the Android working tree on `5c1aa4d` (the catalog source, the `strings.xml` files and the
`journey.xml` files it compares), as they are on disk, `sha256sum <path>`. All have CRLF line endings.

```text
b29f4ad75c40dfdc0a68f46cba4e49e36e8c25b873f4d242b9f5a98cd2ae27de  app/src/main/java/com/appsbybros/minik/localization/AppText.kt
645a460fc1dcd1887382e1008e27c0ca52ca0a08bf02d8ad3014abcfbf42c499  app/src/main/res/values/strings.xml
bc4081936b6ffab846eb9f97fe34e770a76939ead1694f001972aebdaf2300c0  app/src/main/res/values-ar/strings.xml
f05df446c7442e08358a943618438dbd6ecd26ad0645402a401bada51a64f553  app/src/main/res/values-es/strings.xml
fa85d402a42b1d09e7cb0bfe6c6097438be919561ecbaadd1457c772a458f533  app/src/main/res/values-hi/strings.xml
bf69da158d624f8900fcb9897b131d24b8391856a461f55d01e87acb69ab21c1  app/src/main/res/values-nl/strings.xml
1d697c98905cef94d93a6abf968aa0f7e6cd4a92dbde946c6879f57dbf791186  app/src/main/res/values/journey.xml
b566fe5cbeb7be75037ac0f763085cee750e4193d9c081e98d4eb58b88d1abb8  app/src/main/res/values-iw/journey.xml
b87334923e2cfe44492ac5b829cff165157ea9dfff859fcb9b1c8ce282d3c807  app/src/main/res/values-ar/journey.xml
74b3b3d17ec1fa5667a122612ab18e9c40f95cf8b113eb8c86b13f8bfd5a20ce  app/src/main/res/values-es/journey.xml
30d0d353e7ba817ea40bfa8abbb1763c948d6e4008459f5371a5804b83a788a3  app/src/main/res/values-hi/journey.xml
be595abdc338a2f48b75760ed718a42dcbb8843d68e4ee15a8842a932bbcf10e  app/src/main/res/values-nl/journey.xml
```
