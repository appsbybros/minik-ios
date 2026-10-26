# Modern Ping Pong iOS implementation — 2026-09-28, updated 2026-10-26

**Implemented in source only. Nothing in this document has been compiled, run in a Simulator or on a device, or played between iOS and Android. The Windows source audit and the local-emulator Firebase rules tests pass. An Apple build and native runtime verification are still required. No IPA was produced.**

## 2026-10-26 sync: Android commit `24cd461`

iOS now matches Android MinikPingPong `24cd461` (4 commits after `6c8c757`). Ported:
- **Zoom keeps both players whole** (`MPReception.swift` `keepPlayersVisible`, `MPScene.swift`; 579de33): while the optional reception zoom is on and nothing is touched, the zoom is limited and the frame shifted so the far player's head and the near player's feet stay on screen. Difference: Android also stopped clipping at the court's top so the far player may draw under its transparent score/HUD; the iOS court is its own SpriteKit view and cannot draw beyond its edges, so the court's own top and bottom (6 pt margin) bound the frame instead. The zoom is therefore a little smaller than Android's when the HUD is above the court.
- **Comet, June and Mia champions** (`MPRanking.swift`, `MPPracticeTable.swift` `MPChampionKit`; 84592d0): Orange, Green and Blue are defended by Comet, June and Mia with the established difficulty; their clothes take the rank colour (Mia has her own brighter fabric test). A champion trial saved before the update (Gaya/Flare/Kyra, legacy or boosted) still counts.
- **Rank wording and menu** (`MPRankViews.swift` `MPRankHero` / `MPRankSheet`, `ModernPongView.swift`; 95ba112): "Points" and "Current ranking" in white beside the mascot (not tappable), an ordinary "Color ranking" button, the sheet titled "Color ranking", White/Yellow explained in one line, and the champion named beside its coloured portrait.

Not ported: the version bump to 1.0.9 (iOS uses the shared `MINIK_MARKETING_VERSION`), store images, emulator device tests and QA evidence. `Scripts/audit-modern-pong.py` now reads Android at `24cd461` (268 checks, PASS). `ModernPongFoundationTests` expects the new champions and adds `testEarlierChampionTrialsStillPromote`; type-checked, not run.

## 2026-10-25 sync: Android commit `6c8c757`

iOS now matches Android MinikPingPong `6c8c757` (13 commits after `29f5dc7`; the app-code commits are `c9f5fa6`, `38b58b4`, `496a709`, `f0ea4aa`, `838c209` and `3010b3e`; `85e3a78`, `d5db032`, `204a645`, `c284042`, `7ecdd5a` and `2b1f48b` are store captures, captions and QA evidence, and `6c8c757` records Android 1.0.8 and QA scripts). Type-checked on Windows against the iOS 26.5 SDK; **no XCTest, Simulator, device or iOS↔Android session has been run**.

Ported:
- **Edge serves and returns** (`MPTableMotion.swift`, `MPEngine.swift`, `MPPhysics.swift`, `MPPlay.swift`; c9f5fa6, 496a709): a serve to the outer edge is answered by one 45–70 % roll set by the receiving hand's skill (`MPServeDifficulty.adjust(handSkill:)`, singles and teams; the served hand is judged from where the receiver stood; no extra placement factor on a served ball). The house player may stand beside the table (`MPProjection.besideTable/legalBody/clampBody`), plans with either hand and intercepts a short wide serve at the sideline. Flights: a bounced ball may be returned beside the table (−0.30…1.30 × −0.24…1.24); a legal return from outside a sideline is judged at its landing, not in the air; a second bounce beyond the tabletop is unreturned; a ball passing beside a net post is not a net fault; contacts keep their real height (at least 0.001, was 0.055); balls that leave the table are ringed; the team rally tail only bounces on the tabletop. The near strip extends beside the table (`strikeZone` x −0.24…1.24) and footwork drags may step there.
- **House-player footwork** (`MPEngine.swift` `MPMotion`; c9f5fa6, 496a709, f0ea4aa): routes go around the table's far corners, never across it; speed is bounded (recovery 850 × movement, interception 1100 × movement, smoothstep peak 1.5 × the average) and recovery starts after the return's follow-through, during the outgoing flight (local matches only).
- **Grounded house player** (new `MPGroundedRival.swift`; `MPScene.swift`, `MPLargeMatch.swift`, `MPPracticeTable.swift` `floorSupports`; 496a709, 38b58b4, 3010b3e): in a local match on either table the opponent is drawn with its full pose atlas, feet on the floor around the table — the complete body under the tabletop, and the part outside it, above its foot line or around a contacting racket on top. Its drawn racket must reach a planned contact (`engine.botCanReach`). On the original court the full arena image is drawn behind it and the table is cut out in front. Online opponents keep their drawings; beside the table they are revealed above the table plane (compact court: an explicit union of mask shapes, as 38b58b4; large table: above the racket's table line).
- **Champions** (`MPRanking.swift`, `MPPracticeTable.swift` `MPChampionKit`, `MPSinglesArt.swift`, `MPColorChallengeView.swift`, `ModernPongView.swift` `MPAvatar`; c9f5fa6): a champion is never weaker than the character's own profile; champion tuning strength is 0.25 + 0.75 × (target − 5) / 6; a win against the pre-update (legacy) champion still counts; Kyra, Gaya and Flare wear the colour they defend (fabric recolouring of the portrait and the in-match atlases).
- **Color Challenge** (c9f5fa6): only the colour names are coloured; a completed part (house-player wins or streak, champion wins) hides its rules and opponents and cannot be started again; "Win once more / Win N more against the … Champion"; "Choose your opponent below: <names>"; the Champion's Play button is on its colour.
- **Daily journey** (`MPPlay.swift`, `MPJourneyView.swift`, `MPPracticeView.swift`; c9f5fa6): each completed journey is revisited with the next control difficulty (Beginner, Starter, Standard, Pro; `cycleControl/control/available/nextStep`; stored stage ids unchanged); stages that need a control not yet taught are skipped; Beginner stages hit automatically after a move (`practiceInput`, saved in the snapshot); Starter/Standard stages also prepare aimed swipes; no three-miss retry; practice starts directly (the instructions button shows the briefing plus the control and its explanation); the brief and the list are rewritten (stage number within the cycle, control difficulty, practice partner; the free-paint entry, the intro and "Back to your challenge" are gone); misses without "/3"; new serve-stage text; plain instruction title; body text from the start edge; selector value 20 pt.
- **Team colours** (`MPArena.swift` `MPTeamColors.Palette/local/online/ink`, `MPTeamRoom.swift`, `MPOnlineTeamsView.swift`, `MPJourneyView.swift`, `MPPracticeView.swift`; f0ea4aa): local team tables use the player's earned colour plus a distinct opponent colour; online rooms keep the host's exact colour and give an equal-rank guest a distinct tint of the same hue (ranks read from `minikPingPong/profiles/<uid>`); names, score, team-picker buttons, the winner caption and the lobby columns use them with contrasting ink. Before a team room opens, the player's rank is published on their profile; a first-ever online player reserves a nickname profile first.
- **Serve taps** (`MPScene.swift`, `MPPracticeView.swift`, `ModernPongView.swift`; 838c209): while a serve is awaited a drag only repositions and a tap serves at finger-up; the Pro hint is "Drag to move. Lift your finger, then tap to serve." (en/he). The OUT cross on the team table is an overlay above players and scenery (white under red).
- **Rooms and setup pages** (`ModernPongView.swift`, `MPController.swift`, `MPRoomsViews.swift`, `MPOnlineTeamsView.swift`, `MPKnockout.swift` `MPControlChoice.explanation`; c9f5fa6): only the selected control is explained (also on the team setups) and only the selected arena's table size; the 75 % serve note is gone; no Cancel buttons on the create pages, the team setup or the team lobby (Back leaves; Back from a never-started friendly room deletes it); Finish only after play has started; explanations read from the start edge.

Deliberate differences / not ported: the Android-only label-centering helpers stay unported — `PongButton` ink offsets (Latin, Hebrew, `latinOffsetDp`, `hebrewMenuOffsetDp`), `PongTextInk`, the `PongRaisedLabel` Hebrew offset, `ExpandButton` lettering, the SettingSelector `PongRaisedLabel` binding and the landscape score's adaptive outline. They correct Android `FamilySkyDrawable` text placement; SwiftUI centres button text in the button itself, and the iOS views (`MPJourneyButton`, `MPChoiceBar`/`MPChoiceGrid`, `MPJourneySelector`, `ModernPongView.action`) have no such offset. Version: Android 1.0.8 is not copied — MinikPingPong uses the shared `MINIK_MARKETING_VERSION` in `project.yml` and never tracked Android's versionName. Android's nickname fix (wait for the profile write) needed no change: iOS `profile()` already awaits it. Strings stay inline English/Hebrew pairs in the Swift sources, as in every earlier sync (the Ping Pong UI does not use `Localizable.xcstrings`). Without the pose art (Math Plus, Minik Plus) the compact court keeps the old house-player drawing and has no visible-reach veto. Firebase rules did not change in this range. The Android checkout currently has uncommitted edits in `ModernCourt.kt` and `ReceptionCamera.kt`; they are not part of `6c8c757` and are not ported.

Verification: `Scripts/audit-modern-pong.py` PASS (263 checks; Android sources and rules are now read from commit `6c8c757` with `git show`, so uncommitted Android work cannot change the comparison; working copies that differ are listed in its report). `Scripts/audit-multi-pong.py` OK. Type-check (Windows, iOS 26.5 SDK): MinikPingPong 0 errors / 6 warnings, MinikMultiPingPong 0 / 2, MinikMathPlus 0 / 0, ProductConfigurationTests with MinikPlus 0 / 1 — the pre-existing baselines. XCTests: new edge-rally, colour, champion, footwork and journey tests in `ModernPongFoundationTests`, `ModernPongParityTests` and `ModernPongTeamsTests` (from Android `EdgeDailyReviewTest`, `EdgeRallyFollowupTest`, `TeamColorRecoveryTest` and the changed `ModernEngineTest`/`PongJourneyTest`); serve-difficulty, champion, journey, doubles, control and restored-snapshot values re-pinned from the Android `6c8c757` classes, compiled on Windows (Kotlin 2.2.21 on Android Studio's JBR) with the scratch harnesses of the previous sync. Authored, not executed.

## 2026-10-24 sync: Android commit `29f5dc7`

iOS now matches Android MinikPingPong `29f5dc7` (50 commits after `739f2f8`; store captures, QA reports, docs and version bumps are not app code). Type-checked on Windows against the iOS 26.5 SDK (0 errors in MinikPingPong, ProductConfigurationTests, MinikMultiPingPong, MultiPongTests, MinikMathPlus, MinikPlus, MinikPlusEnglish); **no XCTest, Simulator, device or iOS↔Android session has been run**.

Ported:
- **Physics** (`MPPhysics.swift`, `MPPongStroke.swift`, `MPTableMotion.swift`): eleven-point matches for every level, Android serve order, Standard swipe shots, assisted tap landings, poor house returns go wide, risky extreme-zone tap serves, Pro topspin/sidespin (`PongStroke`, `PongSpinShot`; flight wire keys `top`/`angle`), finite-radius table edges, loose ball after every point, near-player projection, return placement, serve difficulty, gait.
- **Singles court** (`MPEngine.swift`, `MPScene.swift`, `MPLargeMatch.swift`, `MPSinglesArt.swift`): four arenas (Beach and Castle keep the compact table, Indoors and Park use the daily table through `LargeMatchRenderer`), your own avatar from behind in Standard/Pro, relative footwork drags, Standard swipe and buffered taps at the baseline, Starter's earlier preparation, Pro gesture strokes, held serve ball hidden, names beside players, spin stripe, castle foliage, landscape framing. Guide: topspin and sidespin lessons (11), new demonstrations. Rank cues `rank_trumpet`/`rank_win`/`rank_big_win`.
- **Team and daily journey** (`MPPlay.swift`, `MPTeamMovement.swift`, `MPPracticeView.swift`, `MPPracticeTable.swift`, `MPJourneyView.swift`, `MPOnlineTeamsView.swift`, `MPTeam.swift`, `MPTeamRoom.swift`): 34 stages (Pro spin, Standard swipe/pace) with catalogue migration, per-seat controls, diagonal serving and wrong-half faults, yielding/retreating teammates with swept collisions, reachable visible-paddle contacts, arenas, team colours, result and instruction pages, control/arena on team setup and online rooms (`meta.arena`, `stroke`/`control` inputs as Android).
- **Rooms, menus and ranking** (`ModernPongView.swift`, `MPController.swift`, `MPRepository.swift`, `MPMultiplayerModels.swift`, `MPRanking.swift`, `MPArena.swift`, `MPRoomsViews.swift`, `MPRankViews.swift`, `MPMatchResultView.swift`, `MPColorChallengeView.swift`): room `arena` (immutable, written only when set), Starter control (4-way choice), friendly setup page with replay, tournament standings with scored/conceded/difference, podium and fixtures expander, rank colours and the Color Challenge (twelve ranks, qualification streaks, champions, promotion celebration) with `rankPoints`/`rankLevel` on the profile, result panel, landscape HUD and help tips, Mega Minik / Mega Miniko.
- **Art and sounds**: arena backgrounds (`Resources/ModernPongArt/arenas`, standalone only), redrawn Minik frames and pose atlases (Multi Ping Pong keeps the old frames as `mpx_*`), rank sounds. Firebase rules copies and tests equal Android `29f5dc7` (local emulator: 76 passed).

Deliberate differences / not ported: Android-only label-centering helpers (`PongButton`, `PongRaisedLabel`, `PongControlLayout`, SettingSelector chevron, ExpandButton lettering); `ic_back_bold` (no iOS equivalent); device-test hooks; in iOS a friendly match against a house player stays a local match (Android creates a local room) — ranking pays the same; team courts draw the arena behind the court view, so the castle foliage, camera-synchronised scenery and gutter name labels are singles-only.

Verification: `Scripts/audit-modern-pong.py` PASS (247 checks; it now also checks that every Android file it reads equals its committed blob at `29f5dc7`); `Scripts/audit-multi-pong.py` OK. New/updated XCTests (`ModernPongFoundationTests`, `ModernPongParityTests`, `ModernPongTeamsTests`, `ModernPongRoomsTests`) pin values from the compiled Android 29f5dc7 classes — authored, not executed.

## 2026-10-13 sync: Android commit `739f2f8`

iOS now matches Android MinikPingPong `739f2f8` ("Improve team rallies, live lobbies, daily practice and store presentation"), which also carries `2b44d71` (already ported in `bf62011`), `e09b052` (versionCode only) and `9be4c84` (store assets only). Not compiled.

Ported:
- **Ball assistance** (`MPReception.swift`): three choices, all off by default (zoom for my return, gentle slow motion for my return, zoom for another player's return). One shared clock: the 1v1 engine scales its whole step; online the authority owns it, sends it as `engine.reception` and checkpoints every 100 ms while it may be active; each human publishes `minikPingPong/receptionPreferences/<uid>` = `{version: 1, slow}`. The zoom is an `SKCameraNode` (backdrop stays still), frozen during a touch, off with Reduce Motion. Settings in the 1v1 settings sheet and the new Settings page.
- **Daily skill journey** (`MPPlay.swift`, `MPPracticeView.swift`, `MPJourneyView.swift`): Android `PongPlay`/`PongJourney` with the thirty stages, paint battles, shapes, streaks, three-miss retry, stars, daily bonus and receipts, saved practice, the paint playground, instructions and the result page with its celebration.
- **Team play**: two against two with the house players ("Take turns hitting" / "Either teammate can hit"), lanes, rally endings that keep the ball moving for 1.65 s, the team celebration. The table is drawn like Android's `PongPracticeView` (Core Graphics) with the new full-body pose atlases.
- **Online team game** (`MPTeamRoom.swift`, `MPTeam.swift`, `MPOnlineTeamsView.swift`): the `minikPongTeams` protocol (`pong-doubles-v1` and the flexible `-lobby-v2` lobby): create/join with a code, copy and invite, two team columns arranged by the host, automatic readiness, Start, Cancel, host-authoritative snapshots (`PongPlay.save()` JSON) and inputs (16-digit keys). Same wire as Android, so iOS and Android phones share a table.
- **Menus and rooms** (`ModernPongView.swift`, `MPController.swift`): four sections (Start & learn, Play, Saved games, Advanced) on quiet gray-to-navy panels with the section colours, remembered open/closed; Daily skill journey, Play as a team, Settings · Feedback & sharing (sounds, menu music, ball assistance, rate/share/feedback behind the grown-up gate); menu music (`pong_menu_remix`, 22 %); pale footer links. New tournament → Create room (own settings page with Cancel) / Room code + Join room, dashed divider; friendly form also joins with a code. Waiting tournaments show a skills table with the red X and a persistent house-player picker; Delete/Leave is pink, after Start, and confirmed; Back from an unfinished tournament asks Save / Don't save / Cancel; matches against house players say "Not started" and offer Start; friendly rooms offer Save for later only after play started and Cancel/Finish in pink. Portraits use the first front pose of the new atlases (old sheets where the art is not bundled, e.g. Math Plus).
- Guide: "Learn team play" on the first lesson card. Firebase rules copy, tests and audit updated.

Deliberate differences: Android's Save/Don't save dialog and Create/Join divider are shared family widgets; iOS uses a system alert and its own dashed divider. The art (`Resources/ModernPongArt`, a folder reference, 37 MB) is bundled with Minik Ping Pong only. Android's unused `WholePlayerArt`, `cross-art`, `whole-players.png` and `legs_*.webp` are not ported (no Android code draws them). Not ported (family-owned): the landscape suggestion toast, the "More below" scroll cue, the raised "sky" drawables. The Android lineup rules test (`lineup.rules.test.cjs`, absolute paths to a cross-app candidate file) is not copied.

Verification on Windows: `Scripts/audit-modern-pong.py` PASS (220 checks). The doubles and journey logic was transliterated line by line from the Swift into Python and matched traces from the compiled Android classes exactly (6 house-player doubles runs × 10 s, all 30 journey stages); the same Android values are now XCTests (`ModernPongTeamsTests`), with Kotlin `Random.nextDouble` reference values and an Android snapshot that iOS restores and continues.

> Follow-up on 2026-09-28: this Modern-only unit is committed locally as `b15717f`. The subsequent Retro unit now routes Math through a chooser: current Modern in Simple mode, or current shared 80’s game. Modern Full remains standalone and contains no Retro menu. The historical “Math unchanged” statements below describe the earlier unit, not the current routing. See [the Retro handoff](retro-pong-ios-handoff.md). Retro adds no ads.

## 2026-10-02 re-sync: Android commit `7f5dd0a` (final, verified on Pixel 3 and Pixel 6)

Android committed the working tree below as `7f5dd0a`. Against the SHA-256 list in the next section, only `multiplayer/PongModels.kt` and `multiplayer/PlayActivity.kt` changed, plus the new `LobbyPauseTest.kt`: returning from a court to its lobby could leave the other phone playing, because lobby presence counted as an active court connection.

| Android | iOS |
|---|---|
| `Session.needsLobbyPresence(uid)`: a human member with no PLAYING match | `MPSession.needsLobbyPresence(_:)` |
| `PlayActivity.syncLobbyPresence` on every room update while in the foreground | `MPController.syncLobbyPresence(_:)` when entering a room, on each update outside the court and on return to the foreground. iOS keeps one presence for lobby and court, so a court that is about to launch keeps it instead of dropping and reopening it; Back from the court already released it. |
| `LobbyPauseTest` (both tests) | `testLobbyPresenceIsDroppedWhileThePlayersMatchIsPlaying`, `testAnotherPlayersMatchKeepsAnIdleTournamentPlayersLobbyPresence` |

Not compiled or run on iOS yet.

## 2026-10-02 update: knockout, controls, rally variation, confetti and completion (Android working tree over `e9fd931`)

Ports the **uncommitted Android working tree** of 2026-10-01 (Android reports `artifacts/knockout-20261001/report.txt` and `artifacts/modern-controls-20261001/report.txt`). Android HEAD `e9fd931` itself only added Android AdMob IDs after `202b808`; `app/build.gradle.kts` is Android-only and ignored. The knockout Realtime Database rules of this working tree are **already live in production** (owner, published 2026-10-01; approved merged-rules SHA-256 `eb60d8c5…750b`), so the wire format below is the live contract. Android is not final (occasional twitch and online lag/double-hit feel are still being investigated there); this is the state as ported — see the SHA-256 list below for a later re-sync diff.

Files changed: `Sources/ModernPong/{MPController,MPEngine,MPMultiplayerModels,MPPhysics,MPPreferences,MPRepository,MPScene,MPTutorial,ModernPongView}.swift`, new `Sources/ModernPong/MPKnockout.swift` and `Sources/ModernPong/MPKnockoutBracketView.swift`, `Tests/ProductConfigurationTests/ModernPongParityTests.swift`, `Tests/ModernPongFirebase/{rules/merged.json,rules/pingpong.json,tests/rules.test.cjs}`, `Scripts/audit-modern-pong.py`, this document.

| Area | Now in iOS source | Android reference |
|---|---|---|
| Knockout room | `MPTournamentFormat` (`ROUND_ROBIN` / `KNOCKOUT`), `MPSession.format`, `.rounds`, `.knockout`. A knockout has 2–9 players and one leg; only tournaments keep a format; a knockout is complete when its state is `FINISHED`. Round robin stays 2–8 with one/two legs. | `PongModels.kt:58-70,248-253`, `Knockout.kt:6-13` |
| Draw and settle | `MPKnockout` (new `MPKnockout.swift`): match ids `<code>_K<round>_<pair>`; seed = `"<code>:<createdAt>:<round>"` folded from 29; `MPKotlinRandom` reproduces Kotlin `Random(seed)` (XorWow) and `shuffled`, so iOS draws the **same** pairs and bye as Android for the same room. Last player of an odd draw has the bye. `settle` finishes house-player pairs with `MPRules.simulate`, gives a departed player's opponent a walkover (`CANCELLED`, no score), and redraws only after every match of the round is terminal; `MPRules.start/finish/leave` route knockouts through it. | `Knockout.kt:14-75`, `PongModels.kt:115-163` |
| Wire (live rules) | Only a knockout writes `format: "KNOCKOUT"` and `rounds/<n> = {count, players[]}`; round robin and friendly rooms omit both (the rules reject them). Decoding accepts RTDB arrays or keyed maps for `rounds` and `players`; any other `format` reads as round robin. Matches keep the existing fields and `authorityUid`. | `PongCodec.kt:31-48`, `firebase/knockout-rules.cjs` |
| Texts | Stage names (Round of 9 / Quarterfinals / Semifinals / Final), advancement, player status, completion headline with 1st/2nd/3rd…, control titles (`MPControlChoice`), `MPMatchText.result` direction isolates. English and Hebrew strings copied exactly; the audit checks every Hebrew literal of the new Android files. | `Knockout.kt:76-100`, `CompletionText.kt`, `ControlChoice.kt:6-11`, `MatchText.kt` |
| Tournament form and room | Format picker (remembered, `knockoutFormat`), knockout players 2–9 (default 8) with the draw explanation; lobby shows "Controls: …"; knockout roster grid before the start, then remaining matches + stage, the player's status, own match and the bracket (`MPKnockoutBracketView`: rounds, bye cards, winner card, connectors along actual winners; sideways scroll, Hebrew starts at the right). Round robin with no remaining own match says "Your matches are complete…". | `PlayActivity.kt:271-305,428-555`, `KnockoutBracketView.kt` |
| Results | Room-match result: completed headline / "You reached the …!" / "You won this match!" / "Match finished", players and score, one action: **View bracket** (completed knockout → its room), **Done** (completed round robin or friendly → dismissed, menu), **Continue** (tournament continues). Header Back = that action. In-match status is prefixed "‹stage› · ‹control› ·". Completed room screen: headline and **Done** only (Back does the same). | `PrivateMatchActivity.kt:59-92,135`, `PlayActivity.kt:81,438-446` |
| History, notices | A completed room is never kept in Your games / Your tournaments (`completed` flag, `dismissResult`; local copies removed on Done/Back and at refresh). Routine notices (inactivity, other players' results, deletions) and the "Updates" panel are retired; errors still use the alert. No automatic `lastCompletedMatch` save. | `RoomBook.kt`, `PlayActivity.kt:594`, `ModernActivity.kt:131` |
| Confetti | `MPVictoryConfetti` (SwiftUI Canvas: 75 pieces, 2.8 s, last 0.8 s fade, non-interactive) after the ad for every won local or room match, and once per completed room (`firstCelebration`). Skipped when iOS Reduce Motion is on (iOS convention; Android has no such check). Simple mode returns to its host and shows none. | `VictoryConfetti.kt`, `ModernActivity.kt:134-137`, `PrivateMatchActivity.kt:85-89` |
| Controls | Beginner/Standard: a horizontal move ≥ 0.012 aims (dx / 0.085, ±2), no forward/vertical gate; Standard keeps the fastest finger movement → up to +35 % pace (Beginner none); no sideline clamp (inherited ±0.25, aim × 0.70) so wide shots can go out; aim/velocity reset and `tapStart = paddle` after contact. Room matches play `MPLevel.control(difficulty)`. Control descriptions updated (EN/HE). | `ModernEngine.kt:84-102`, `ModernGame.kt:316-382,404-427`, `ControlChoice.kt:6`, `PrivateMatchActivity.kt:117`, `PlayActivity.kt:298` |
| Rally variation | `MPRallyVariation`: the 5th straight committed return in the same lane (|vx|/|vy| ≤ 0.09, lane 0.10) gets +28 % of forward speed toward the centre, once. Applied by the striker on both sides; remote/acknowledged flights are only counted (`adjust: false`); reset each rally and on a point change/reconnect. | `RallyVariation.kt`, `ModernGame.kt:97,279,423,449,461,478` |
| Animation | Minik's FOLLOW pose cross-fades into READY over 0.16 s (`MPStroke.recoveryBlend`, `MPScene.recoveryNode`). Finger follow-through never re-plans Minik's movement (iOS never did). | `ActorPresentation.kt:58-59`, `ModernCourt.kt:214-256` |
| Guide | Demo swipes: sideways 0.013 (left→left), 0.13 (right→left), 0.055 (left→middle), 0.065 (middle→right), movement (±1.8, −1.7), then finger up. | `ModernTutorial.kt:80-91` |
| Firebase rules copy | `Tests/ModernPongFirebase/rules/merged.json`, `rules/pingpong.json`, `tests/rules.test.cjs` = Android working tree (test paths localized); `merged.json` SHA-256 equals the live-approved `eb60d8c5…750b`. | `firebase-setup/merged-database-rules.json`, `firebase/pingpong.rules.fragment.json`, `firebase/tests/rules.test.cjs` |

Not ported or intentionally different: Android's new sentence "Choose your house players on the next screen." (the iOS form never carried the old one); Android `committedAim` (only used by guide lessons without a target zone — none exist; iOS checks landing zones); Android Spinner callback fix (no SwiftUI equivalent needed); Reduce Motion skips confetti. Mirrored Android quirk: a legacy room with difficulty 1 or 2 plays Standard input while final-score validation still uses the stored level (only pre-update rooms).

### Verification for this update (Windows)

| Check | Result |
|---|---|
| `python -B Scripts/audit-modern-pong.py` | PASS: 201 checks (16 new: knockout bounds/ids/seed/shuffle/wire/live rules, rally, tap power and aim, recovery, guide distances, confetti, history, control level, every new Android Hebrew text) |
| Firebase rules (`merged.json` + `rules.test.cjs`) on the **local** RTDB emulator `demo-minik-pingpong` (cached `firebase-database-emulator-v4.11.2.jar`, Android Studio JBR, Android `firebase/node_modules` read-only via `NODE_PATH`, temporary copy) | PASS: 54 tests, 0 failures (knockout sizes 2–9, draws, byes, walkovers, cascades). No production contact; Android tree unchanged |
| Knockout draw parity | Reference values from the real Kotlin stdlib (`kotlin-stdlib-1.9.23.jar`, Java 25 from JBR); a line-by-line Python transliteration of `MPKotlinRandom`/draw seed matched all 25 cases; the same values are XCTest assertions |
| Physics expectations | Python transliteration of the changed iOS shot/flight/engine paths: all six guide return lessons succeed with the new demo gestures; Beginner sideways, Standard power ratio 1.25, edge shots out, long swipes cross, controlled cross-court reachable, plain tap keeps direction |
| `ModernPongParityTests` | 71 XCTest methods: 28 new (three replace the removed opposite-sideline test, whose clamp Android deleted), the guide test updated; **not compiled or run** |
| Xcode build, Simulator, device, iOS↔Android live knockout, `Scripts/swift-windows-check.py` | **Not run** (no Swift toolchain on this machine) |

### Android state ported (working-tree SHA-256, 2026-10-02)

```
97e6c175c9bcfde4eb07e42150a9b5306e889cca8ed46df5c74446a49947a197  app/src/main/java/com/appsbybros/minik/pingpong/ActorPresentation.kt (M)
ceb76971f7db7ab0b653ff950daf20f1273362352f1b6fc00ab1535b9b0d02fe  app/src/main/java/com/appsbybros/minik/pingpong/ModernActivity.kt (M)
d670bf97dff1c82dff8574073e354024315eb40796ae9d363167103790b8654d  app/src/main/java/com/appsbybros/minik/pingpong/ModernCourt.kt (M)
169553e83d4b6db84cd2fadefe0002f3d8d0a73cf8c5d088d6c490c27d14fa04  app/src/main/java/com/appsbybros/minik/pingpong/ModernEngine.kt (M)
9f48509322ca7c9b78ac9c0bc9d0c390f414c4e4e42c6a839460053666bbad6f  app/src/main/java/com/appsbybros/minik/pingpong/ModernGame.kt (M)
2dc6e620d4fffe644beff37ec3efc4cc7255b3036db01abd34c4a6c5407cb3e7  app/src/main/java/com/appsbybros/minik/pingpong/ModernTutorial.kt (M)
948f4ce9e37c370e52ddfa428ee195aabbf0067aa169a2d0509554cda0370dc0  app/src/main/java/com/appsbybros/minik/pingpong/RallyVariation.kt (new)
37be9d496034a3b9aaaac518077d62146996270c88a50fc828d9972547a55d4a  app/src/main/java/com/appsbybros/minik/pingpong/VictoryConfetti.kt (new)
908ad6833cf8b5ca708cd7be3624b7f41304ec08127e40688f9b18a473c7e421  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/CompletionText.kt (new)
38e45acb652bb02bd3971c0105b1222597e1e99910dede2c5c0b0a695b744ee5  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/ControlChoice.kt (M)
2a6f399b6a4fb41afaa6cca6e1b5c52fce62495160157f9401fd9c7260e96315  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/Knockout.kt (new)
830e7ec204c7bfa49974dda54612e24534b8c5f8622c793808f2e510edb8bbf0  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/KnockoutBracketView.kt (new)
5473cc87433ab262a7d2c9aaf125206a20d579ec509041189f665df52d13ea55  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/PlayActivity.kt (M)
1e0682a44e70198cf2d66480199326dc0e92d64454397487604ec6a0072446f0  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/PongCodec.kt (M)
e6b3e888ecef9a74407076470fc9ae6e030ec178ea8b53682ed342f96cd0752b  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/PongModels.kt (M)
1add0d2b5229570d564bc7dff2bf77ca637971202a78378759d6cbbfc39dd5d8  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/PrivateMatchActivity.kt (M)
254ad8380f31fb7f494c5d3c24f089199714afd8cb0e02341dbe6b0dec4e2c34  app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/RoomBook.kt (M)
70e7d70943027ebb2f02908d81362519d9a2fbf2b25d83376fbc598ddda767c5  app/src/test/java/com/appsbybros/minik/pingpong/ControlAndCompletionRegressionTest.kt (new)
1b6fa92e5b406e7e03f8711f4ee01e28bfea71856ac31c46429b06163da1abf2  app/src/test/java/com/appsbybros/minik/pingpong/KnockoutTest.kt (new)
199506c5ce09639a04708eb58ec095e523bfa76fdbf2024a916eef0725bc76be  app/src/test/java/com/appsbybros/minik/pingpong/ModernFollowupTest.kt (M)
d3eb80365ebe7fcbef01ab24dada8e41c88e84a6eae8740b5257712fc1b338cb  app/src/test/java/com/appsbybros/minik/pingpong/ModernTutorialTest.kt (M)
8925732a5b5756934ab86a836fd7b4e18b75a6e24034ec3e3a11e3e48e8454b9  firebase/generate-rules.cjs (M)
3fd8fc1264b8e5fa2fb7f175eb2df21bd32c77f246dc76b738cc1f831d3e6bc0  firebase/knockout-rules.cjs (new)
3140d5cd23bf4d4030ca188cc730435cd743c502f1d3d49d08d9034e4401db83  firebase/pingpong.rules.fragment.json (M)
8794b6b67944d93a45fb8c806fcda7a59e4afd590e1f61c08c896176b9308c54  firebase/tests/rules.test.cjs (M)
eb60d8c525bf443018dff3c1a420b3646dc323f06cd4240aea6d8c70fa48750b  firebase-setup/merged-database-rules.json (M; live-approved)
940de3346a8d45a74f971d933efbaa6c83264985ced79f449c65b7b80b01533d  firebase-setup/current-database-rules.json (unchanged)
```

Follow-ups: an Apple build and the new XCTests; an iOS↔Android knockout with two humans (draw identity, walkovers, the final's completion screen); the Android re-sync once its twitch/online-feel work lands.

## 2026-10-01 update: current Android parity (Android HEAD `202b808`, 09-29 changes)

Owner decision 2026-09-28 (`MINIK_MASTER_PLAN.md`, end of Part X): port the current standalone Android Modern Ping Pong. The iOS port of 09-28 predated Android's 09-29 changes. This update ports them. Files changed are limited to `Sources/ModernPong/*`, `Tests/ProductConfigurationTests/ModernPongParityTests.swift`, `Tests/ModernPongFirebase/**`, `Scripts/audit-modern-pong.py` and these two docs.

| Area | Now in iOS source | Android reference |
|---|---|---|
| Beginner level | `MPLevel.beginner` = wire/room ordinal **4** (appended; 0–3 unchanged). Beginner uses the STARTER tuning. After the legal receiving bounce the return is automatic when the ball is in the player's zone (y 0.72–1.0) and the paddle (held or last released position) is within 0.16; one contact only; a diagonal drag still aims. Child serves first; targets 3/5/7/10; **no two-point lead**. | `ModernEngine.kt:15-19`, `ModernGame.kt:35,201-213,314-325`, `Tuning.kt:81-83` |
| Scoring / rooms | Two-point lead only for Android MEDIUM/HARD (iOS `.hard`/`.superHard`). `MPRules.validFinal` follows the room level, so an iOS-authority 7–6 Beginner result is valid. Room difficulty is clamped to 0…4 on create and decode. | `PongModels.kt:74-76,162-166`, `PongCodec.kt:39` |
| Defaults and selectors | Beginner is the default control (rooms, local house matches) and the default practice level. Room/local control picker: **Beginner / Standard / Pro** (Android `ControlChoice` 4/0/3). Practice ("Minik level") picker: Beginner, Easy, Medium, Hard, Super hard. A previously saved Standard/Pro choice keeps its meaning. | `PlayActivity.kt:43,256-266,274`, `ControlChoice.kt`, `ModernActivity.kt:38-45` |
| Guide | Nine lessons in Android order: three serves, **automatic return (Beginner)**, five tap/aim returns; lesson texts and feedback from Android strings. | `ModernTutorial.kt:38-47,83` |
| Stroke window | Beginner/Standard 0.10 / 0.40 / 0.50 / 0.62 (was 0.62 window); Easy 0.52; missed taps can be retried 0.18 s into the swing; an armed tap retargets while the finger moves. | `ModernGame.kt:39-43,314-319,342` |
| Roster | Flare 9 / Kyra 10 in all eight skills; Kyra's Hebrew name **ספיר**; nicknames follow. | `BotRoster.kt:14-16` |
| House players | Opponent level from skill (avg of forehand, backhand, accuracy: ≥9 HARD, ≥8 MEDIUM, ≥7 EASY, else STARTER) with the room level only setting input forgiveness; physics fixed to STARTER (0.40 / 3.6 / 0.54 / 0.075). `MPHouseStrategy` placement/tempo patterns and `MPServeReliability` (no back-to-back Minik faults, same long-run rate). | `PongModels.kt:36-49`, `HouseStrategy.kt`, `ModernGame.kt:36-37,121,272-275` |
| Online | Only the authority awards points (no speculative guest scoring); late-return grace 2.0 s (was 0.65 s); an acknowledgement of the same point/rally/striker never rewinds the local predicted flight; the authority checkpoints on local contacts only. Either human participant may Finish a friendly game (also while playing); a scheduled room accepts no new seat. | `ModernGame.kt:187,282,434-437`, `MatchLink.kt:9,75`, `PongModels.kt:77-78`, `FirebasePongRepository.kt:222` |
| Presentation / audio | Drawn paddle follows the player except for a 0.07 s impact frame, with Android's decaying lateral tilt and full swing angle. The opponent keeps the last swing's hand and translates the ready pose (no step/back walk cycle). Failure sound only for the player's net / left-table / first-bounce-out faults. | `ModernCourt.kt:142-157,210-301`, `ActorPresentation.kt:44-61`, `ModernEvents.kt:63` |
| Tournaments | Standings points per win selector (1–5, default 3); the host can remove a house player before the tournament starts. | `PlayActivity.kt:273,493` |
| Guide auto-show | "Don't show the guide automatically" now works and is saved immediately: like Android `ModernActivity`, the guide opens before a screen's first **local** match (Simple Start, offline Full house match) unless hidden; "To the game" or Back then continues that match. The menu's "Learn how to play" always opens it. | `ModernActivity.kt:49-52,308` |
| Parent gate | "Parents / adults · Remove ads" opens the app's `ParentalGateView`; purchase, restore and App Store code redemption are reachable only after it. | `MonetizationActivity.java:34,65-85` |
| Ads | `.full` (standalone) only; Simple never requests Modern ads. **Production:** when `MinikAdsConfiguration.load(product: .minikPingPong).providerConfiguration` is non-nil (enabled, policy-approved, real IDs, matching `GADApplicationIdentifier`), its interstitial unit is used. **Debug:** Google's sample IDs as before. Requests: child-directed treatment, G rating, personalization disabled. Cadence = Android `AdPolicy` (first two completions free; 2 completions or 210 s active; long-session mode 3 and 300 s; 120 s spacing; malformed IDs and idle time ignored); interstitials older than 55 min are discarded and a failed load waits 60 s, as in Android `AdCoordinator`. | `AdPolicy.java`, `AdCoordinator.java:103-157` |
| CI offline launch | `-MinikOfflineSmoke YES` (UserDefaults `MinikOfflineSmoke`) makes `MPController` use `MPLocalRepository`; normal launches unchanged. The CI workflow itself (not in this scope) must pass the argument. | — |

Wire format re-checked against Android `PongCodec.kt` / `NetworkState.kt` after the 09-29 changes: the only change is the difficulty range (0…4). All engine status strings sent in checkpoints remain Android `GameStatus` names (the Beginner hint is display-only).

### Verification for this update (Windows)

| Check | Result |
|---|---|
| `python -B Scripts/audit-modern-pong.py` | PASS: 185 checks, including all 43 Android asset hashes, AI profiles, roster, Beginner/grace/strategy/serve-reliability constants, guide order, rules snapshot and tests, gate, offline launch and ad policy |
| Firebase rules: current Android snapshot (`merged.json`, `pingpong.json`) and `rules.test.cjs` (paths localized) on the **local** RTDB emulator (`demo-minik-pingpong`), Java from Android Studio's JBR, dependencies reused read-only from Android | PASS: 46 tests, 0 failures. No production Firebase contact |
| 44 `ModernPongParityTests` XCTest methods (19 new and 7 updated for this update) | Authored; **not compiled or run** |
| Xcode build, Simulator, device, StoreKit, AdMob, iOS↔Android live match | **Not run** |
| `Scripts/audit-minik-ads.ps1` | Its one current error is a Google sample ID in the shared `project.yml` template (outside this scope); its Modern checks pass |

Known limits and follow-ups: Android's UMP consent flow and age question are not ported (only relevant once production ads are on); in the standalone app `RootView`'s own `MinikAdCoordinator` (outside this scope) may also start the Google SDK and preload an interstitial it never shows; real AdMob iOS IDs and the owner's enable decision are still pending; a CI smoke step must pass `-MinikOfflineSmoke YES`.

## Scope and entry points

- Writable: `C:\Projects\Minik-to-IOS\ios-main-merge`.
- Behavioral/art/audio reference: `C:\Projects\MinikPingPong` (read-only).
- Standalone `PingPongOnlyRootView` now loads `ModernPongView(experience: .full, commerce: commerce)`.
- `.full` is the default: house players, curated profiles, friendly rooms, tournaments, online play, completed-match ad opportunities and StoreKit purchase/restore/code UI behind a grown-up gate.
- `.simple` shares the same engine, art, controls and tutorial, but never connects its repository to Firebase, never requests Modern ads and has no profiles, online, tournament, room history or associated help text. Choose a house player and Beginner/Standard/Pro, then start (the guide opens first unless hidden). On completion it calls `onClose(result)` once; early exit calls `onClose(nil)`.
- Neither new entry point contains 80s. Existing Math/legacy Ping Pong routes and 80s gameplay/assets were intentionally left unchanged by this Modern-only unit. No Android files, TripleShot files, Git state or attached devices were modified.

Host example, in an app that includes the shared Modern sources and resources:

```swift
ModernPongView(experience: .simple, commerce: hostCommerce) { result in
    // Optional: store/use the result; nil means an early exit.
    showingPingPong = false
}
```

Include `Resources/ModernPongAssets.xcassets` and `Resources/ModernPongAudio` in an embedding target. Simple does not need Firebase dependencies. Pass the host's existing commerce controller so its Apple entitlement is reused. The current Math target is not wired to this view yet; a later embedding change can replace its host route without copying an engine or menu. Sources are shared within this XcodeGen project, not a separately published framework.

## Implemented behavior

- Native SwiftUI/SpriteKit Modern court; fixed 120 Hz simulation, natural diagonal serves, retained lateral tap returns and wide diagonal aiming. Beginner returns automatically when the paddle is in place; Easy/Medium/Hard use forgiving taps and diagonal swipes; Super hard uses precise swipe timing/power. In house-player rooms the UI says **Beginner / Standard / Pro** (Beginner is the default), and opponent skills remain independent.
- Current Android AI profiles and house-player statistics are imported directly; a house player's AI level comes from its own skill, with Android's placement patterns and serve reliability. Movement must reach the actual contact position; current first-middle assistance, per-hand return-speed history, caps, cross-court penalties and rally fatigue are retained. Existing saved control-mode values of the retired 80's game are not consulted.
- Persistent player paddle at the last valid player-side location; serving to a remote target does not move the paddle there. Local input survives network acknowledgments (an acknowledgement of the same point never rewinds the local shot), with a short visual ball reconciliation and Android's 2.0 s late-return grace; only the match authority awards points.
- Current Android art, including all eleven house players: Minik, Flare, Kyra (Hebrew ספיר), Gaya, Mia, Amber, Comet, June, Bouncy Bob / מושיקו, Miniko and Coach67. Names and skill values match the current reference (Kyra 10, Flare 9, Gaya 8, Mia 7, Minik 6). Miniko is the default profile avatar; Minik remains the default opponent/teacher. Current animation sheets, Minik poses and body/arm occlusion masks are reused; footwork translates the ready pose, as in current Android.
- Nine guide exercises: serve middle/left/right, the Beginner automatic return, then middle-to-anywhere, middle-to-right, left-to-middle, left-to-left and right-to-left. Show Me, Try, Retry and Next validate actual landing thirds. English/Hebrew instructions state table side clearly. Native responsive guide controls have a scrollable area and equally sized actions. "Don't show the guide automatically" is honored.
- Pastel menu with consistent bold actions, inline profile/friendly/tournament forms, animated house-player carousel, large +/− history controls, centered captions and a consistent pink Back arrow. Nicknames are curated rather than free text; character avatars influence generated names and remote visuals.
- A unified friendly game and a unified tournament accept humans by code and house players. Copy code, unique house-player selection, three open games/three tournaments, participant presence, Ready synchronization, one start, authority-owned final results, standings, playable fixtures and expandable match history are implemented.
- Friendly selection does not require a second setup screen. A filled friendly room schedules automatically; a house-player match starts immediately, and human matches require both Ready states. Tournament host transfer/deletion rules preserve completed results.
- Background/pause releases audio and presence/listeners; reconnect restores the checkpoint. Results are saved before any ad. Local once-only notices cover inactivity warnings, removal of involved rooms and other tournament results. Fourteen-day cleanup uses the existing bounded queries and server-enforced conditions, not a production admin scan.

### AI profile values

Percentages below are imported from the current Android source. `answer/good` means percentages of **all attempts**, not good conditional on answering. A successful answer's quality draw therefore uses `good / answer`. Physical reach still applies. Same/cross means Minik's previous defended horizontal third versus the new third.

| Profile | Easy | Medium | Hard | Super hard |
|---|---:|---:|---:|---:|
| Forehand serve / successful serve / middle target | 80 / 85 / 80% | 70 / 90 / 60% | 60 / 95 / 20% | 50 / 95 / 10% |
| Serve speed × baseline; variation | 1.00 ±5% | 1.05 ±5% | 1.15 ±10% | 1.20 ±5% |
| Receive serve, backhand | 85/80 | 85/80 | 90/85 | 95/90 |
| Receive serve, middle | 90/85 | 90/85 | 95/90 | 95/90 |
| Receive serve, forehand | 95/90 | 95/90 | 95/95 | 95/95 |
| Forehand same / cross | 90/85; 80/70 | 95/90; 85/75 | 95/95; 90/80 | 95/95; 95/85 |
| Backhand same / cross | 80/75; 70/50 | 85/80; 75/55 | 90/85; 80/60 | 95/90; 85/70 |
| Fatigue per later response | 5 pp | 4 pp | 3 pp | 2 pp; cross backhand good 3 pp |
| First forehand / backhand speed × baseline | 1.03 / 0.98 | 1.05 / 1.03 | 1.12 / 1.08 | 1.15 / 1.10 |
| Speed cap × baseline | 1.22 | 1.32 | 1.52 | 1.68 |

Easy speeds rise 1–3% with 80% probability or fall 0–2%. Other levels rise 2–5% forehand / 2–4% backhand with 90% probability or fall 0–2%. Near the cap the current Android bounded ±5% behavior applies. The complete numeric tuning is `Sources/ModernPong/MPTuning.swift`; the source audit compares all profile numbers and every house-player statistic to Android. Bot-only fixtures use a seeded Swift PRNG, not Kotlin's exact random sequence; the host writes one durable result that all clients share. These probabilities are product tuning, not proof of age-specific win rates.

### Modern audio

This deliberately keeps Modern's event semantics, not 80s train/balloon rules:

| Event | Asset |
|---|---|
| Swing | `minik_kick2` |
| Actual racket contact | `minik_kick` |
| Net | `splash` |
| User net / out shot loses point (not missed receives, second bounces or illegal serves) | `failure_sound` |
| User point | `success_pictures_screen_sound` |
| Third consecutive user point | `success_in_a_raw_sound` (replaces normal point effect) |
| User victory | `minik_claps` |
| Human joins | `connected` |
| Other human Ready | `player_ready` |
| Guide explanation/demo/feedback | `cool_music2`, paused during Try and stopped for a match |

## Firebase setup completed

- Project: `minikswish`.
- Bundle: `com.appsbybros.minik.pingpong`.
- New Apple app ID: `1:12298786440:ios:bfc268456a87978e75f13d`.
- Plist: `Config/Firebase/MinikPingPong/GoogleService-Info.plist`.
- Named client: `minik-ping-pong-ios`.
- RTDB: `https://minikswish-default-rtdb.europe-west1.firebasedatabase.app/`.
- Paths used by the client: `minikPingPong/profiles`, `nicknames`, `openSlots`, `friendlyRooms`, `tournaments` and `live`, all under that same root. No optional leaderboard was added.
- The existing Android protocol-1 field names, room schema, presence slots, action ring, checkpoint revisions and result-authority rules are reused. Cross-platform live compatibility has not yet been runtime verified.
- **Production action performed:** Apple app registration/config retrieval only. No RTDB records/rules deployed or edited, and no TripleShot data modified. Anonymous Auth and production rules had already been enabled/published by the owner.

No missing plist remains. Check any API-key platform restrictions against the real signed Apple bundle on the first iOS run. The Firebase rules copies are verification snapshots, not a deployment instruction.

## Ads, Apple purchase and code behavior

- Modern ads run only in the standalone `.full` experience of the MinikPingPong product. Debug standalone builds use Google's **iOS test** app/interstitial IDs. Release sets `MODERN_PONG_TEST_ADS=NO`. A production path now exists: it activates only when `MinikAdsConfiguration` for `.minikPingPong` is enabled, policy-approved and has real IDs whose app ID equals `GADApplicationIdentifier`. With today's `project.yml` (ads disabled, sample app ID) no production ad is requested.
- First two lifetime completed matches are ad-free. Then ordinary cadence is two completions **or** 210 active seconds; after five recorded sessions averaging at least fifteen minutes, cadence becomes three completions **and** 300 active seconds. There is a 120-second minimum between shown ads. This is Android `AdPolicy`, including its rejection of malformed completion IDs and non-positive activity.
- Cadence persists locally, uses deduplicated match IDs and resets only when an ad actually presents. A loaded ad may appear after a durable completion and before that device's result screen; it does not block the other participant's result or Ready/start. Missing/failed inventory is skipped without waiting; a failed load waits 60 s and an interstitial older than 55 minutes is discarded.
- Child-directed treatment, G rating and disabled personalization are set on every request configuration (Debug and production). No age question, UMP consent form or behavioral upload was added. Simple mode never requests Modern ads.
- Existing `MinikCommerceController` and AppStoreCommerceKit handle `remove_ads`, product pricing, entitlement updates, restoration, pending/cancel/error and immediate ad suppression. Simple accepts the host controller. "Parents / adults · Remove ads" first shows the app's `ParentalGateView`; purchase, restore and offer-code redemption appear only after it is passed, and the gate is shown again every time the sheet opens.
- Codes use Apple's native offer-code redemption sheet. Android/Firebase unlock codes are not Apple purchase codes and were not copied.
- Still needed in App Store Connect: the standalone app record/signing team if absent; its own non-consumable `remove_ads`, localized metadata/price and offer codes; Sandbox/TestFlight validation. Real production iOS AdMob IDs/configuration and privacy/category decisions are also pending.

## Exact files and asset provenance

Machine-readable complete inventory: [modern-pong-changes.json](modern-pong-changes.json), including original/final SHA-256 values. Asset source hashes: [modern-pong-android-assets.json](modern-pong-android-assets.json).

New native source files under `Sources/ModernPong/`: `MPPhysics.swift`, `MPTuning.swift`, `MPEngine.swift`, `MPRoster.swift`, `MPMultiplayerModels.swift`, `MPRepository.swift`, `MPMatchLink.swift`, `MPPreferences.swift`, `MPTutorial.swift`, `MPScene.swift`, `MPAudio.swift`, `MPAds.swift`, `MPController.swift`, `ModernPongView.swift`.

Integration changes: `Sources/PingPongOnlyRootView.swift`, the one standalone call in `Sources/RootView.swift`, `project.yml`, `.gitignore`, `Scripts/audit-minik-ads.ps1`, `Scripts/audit-release-configuration.ps1`. New tests/audit: `Tests/ProductConfigurationTests/ModernPongParityTests.swift`, `Tests/ModernPongFirebase/`, `Scripts/audit-modern-pong.py`. New resources: `Resources/ModernPongAssets.xcassets/`, `Resources/ModernPongAudio/`, `Resources/Privacy/ModernPong/PrivacyInfo.xcprivacy`, the Firebase plist. Documentation changes are listed in the inventory.

The 33 named Modern images and launcher icon use current Android art, converted losslessly to PNG for Apple's compiled asset catalog, rather than assuming SpriteKit decodes Android WebP. Ten sound files are copied directly. The image source payload is about 38.6 MiB before Apple's asset compilation; this is not a measured IPA size. Existing legacy assets remain for their hosts. Pre-edit backups are under `C:\Users\User\AppData\Local\Temp\minik-ios-modern\baseline`.

## Verification actually performed on Windows (historical, 2026-09-28 unit)

The current results for the 2026-10-01 update are in the table near the top of this document. This historical table describes the earlier snapshot.

| Check | Result |
|---|---|
| `python Scripts/audit-modern-pong.py --android C:/Projects/MinikPingPong` | PASS: 152 source/asset/config/profile checks |
| Swift grammar parse of 17 new/changed staged Swift files | PASS: no grammar errors; **not** typechecking |
| Isolated RTDB emulator, copied current rules suite | PASS: 43 tests, 0 failures |
| `powershell -File Scripts/audit-minik-ads.ps1` | PASS |
| `powershell -File Scripts/audit-minik-commerce.ps1` | PASS |
| `powershell -File Scripts/audit-release-configuration.ps1` | PASS |
| `powershell -File Scripts/audit-product-configuration-tests.ps1` | PASS, including existing Math boundary mutation checks |
| 25 focused Modern XCTest methods | Authored and included in the existing test target; **not run** |
| Xcode build, Simulator, iPhone, StoreKit/AdMob presentation, real online match | **Not run**: Apple toolchain/runtime absent on this Windows host |

Rules execution used `firebase emulators:exec --project demo-minik-pingpong --config firebase.json --only database --non-interactive "node --test --test-reporter=spec tests/rules.test.cjs"` from an isolated temp copy. Dependencies were reused read-only from Android; no Android installation/files were changed. Repeat from `Tests/ModernPongFirebase` after `npm install`, using `npm run test:emulator`. Evidence: [Firebase rules test log](modern-pong-verification/firebase-rules-test.log). These tests exercise security fixtures, not the running Swift client.

The XCTest cases cover input mapping, lateral/wide shots, precise-control faults, natural serves, valid paddle bounds, actual tutorial landings/wrong-side rejection, statistical AI ordering/caps, roster strengths, protocol round trips, Ready/authority/immutable results, slots, host transfer, names, ad cadence, Simple callback and friendly auto-start. The 2026-10-01 update adds Beginner ordinal/scoring/room validation, automatic return (and its wrong-side and other-level negatives), paddle tracking, acknowledgement without rewind, authority-only scoring, the 2.0 s grace, match-link authority, Sapir/roster order, skill-derived house tuning, house strategy invariants, serve reliability rates, friendly finish and seat rules, tournament win points and house-player removal, ad-policy input validation, Simple-never-ads, failure-sound mapping, guide auto-show/hide and the offline smoke repository. The strategy and serve-reliability expectations were pre-checked numerically with a Python port of the Swift PRNG. Neither a source audit nor a probability simulation proves real playability.

## Next Apple verification

Use the existing **manual** `.github/workflows/ios-simulator.yml` after the owner commits/pushes these files, or on a Mac:

```sh
xcodegen generate
xcodebuild -project Minik.xcodeproj -scheme MinikPingPong -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/ModernPong CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Minik.xcodeproj -scheme MinikPlus \
  -destination 'platform=iOS Simulator,id=<booted-simulator-UDID>' \
  -only-testing:ProductConfigurationTests/ModernPongParityTests test
```

The repository's complete workflow builds all four flavors and runs the shared test suite once. No workflow was dispatched and no Git mutation was made here. Native compile failures, if any, must be fixed before claiming completion of the Apple validation gate.

Physical/Simulator checklist:

1. Small iPhone, normal iPhone and iPad; English/Hebrew; portrait/landscape. Check menu scroll stability, captions, carousel, guide controls, safe areas, opponent masks and persistent paddle.
2. All nine guide demos/tries (including the Beginner automatic return), natural diagonal serves, tap left/right/straight and full-width cross-court returns. Test Beginner/Easy/Medium/Hard/Super hard and Beginner/Standard/Pro against all house players; confirm the guide opens before the first local match and stays hidden once "Don't show the guide automatically" is on.
3. Simple host: no nickname, room, online or tournament help/UI; no Ping Pong Firebase connection; result callback once, exit callback nil, host navigation restored. Existing Math/80s screens remain intact.
4. Two real clients in the **same** room: iOS as authority then Android as authority, including a Beginner room that ends 7–6. Check profile/character animation, code copy/join sounds, Ready sound, exactly one start, serve/return trajectory, paddle acknowledgment behavior (no rewind or duplicate hit), no guest-side point before the authority's checkpoint, and identical final scores.
5. Background/resume and force-kill/re-entry during play; no duplicate results, ghost presence, overlapping audio or repeated ad.
6. Tournament with two humans and house players: roster, schedule, bot-only results, one human fixture, standings, leave/re-enter, host transfer and delete only when allowed. Three-room limits, warning/deletion/result notices once.
7. Google test ad at a completed-match boundary; failure/offline skips; result remains saved; Simple (Math) never shows a Modern ad. The grown-up gate appears before purchase/restore/code; Cancel closes it. Purchase/cancel/pending/restore/revocation/offer redemption in StoreKit Sandbox; removed ads stay suppressed.
8. Inspect Xcode logs for Firebase/Auth/RTDB and resource errors. Confirm all new writes are under `minikPingPong/`; no TripleShot or Language collections changed.
9. Launch with `-MinikOfflineSmoke YES`: no Firebase sign-in or writes; local rooms only.

Official implementation references: [Firebase Apple RTDB](https://firebase.google.com/docs/database/ios/read-and-write), [Google iOS test ads](https://developers.google.com/admob/ios/test-ads), [Apple offer-code support](https://developer.apple.com/documentation/storekit/supporting-offer-codes-in-your-app).
