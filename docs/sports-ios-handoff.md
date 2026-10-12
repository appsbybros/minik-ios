# Minik Squash and Minik Beach Volley — iOS port handoff

## Port of 2026-10-13

Both apps are one Android project, `C:\Projects\MinikSports` (the `sports` library module with the
`squash` and `volley` app modules; the working tree at 0b77b1e with its uncommitted changes). On
iOS they are two targets built from the same `Sports/` sources; the Info.plist key `SportsGame`
(`SQUASH` or `VOLLEY`) picks the game, like the Android manifest's `sports.game` meta-data.

| | Minik Squash | Minik Beach Volley |
| --- | --- | --- |
| Target / scheme | `MinikSquash` (tests: `SportsTests`) | `MinikBeachVolley` |
| Bundle ID | `com.appsbybros.minik.squash` | `com.appsbybros.minik.beachvolley` |
| App icon | `SquashIcon` (from `art/squash-icon-source.png`) | `VolleyIcon` (from `art/volley-refinement/launcher-berry-source.png`) |
| RTDB root | `minikSquash/` | `minikBeachVolley/` |

Nothing was compiled on this machine (no `swiftc`): everything was written and checked by reading,
tree-sitter parsing, `Scripts/audit-sports.py` and an independent line-by-line review of every
Swift file against its Kotlin original. The compile check builds both apps and runs `SportsTests`
on a simulator.

## What was ported

| Area | Status |
| --- | --- |
| Simulation (`SportsEngine`): squash wall/floor physics, tin/out/two bounces/floor-first faults, serve questions (serves only or every hit with slow motion; own / full time / until the serve), answer windows, learning points, beginner/standard/pro control, house players, tutorial stages, reception focus and slow motion, scoring, ranks and receipts | Ported statement by statement, same constants and Kotlin `Random` order |
| Volleyball (`VolleyPlay`): serves (beginner, automatic toss with one retry, pro toss and swipe with the 10 s deadline, jump serve), receive/set/attack with at most three touches, smart passes, double-tap sets and spikes, blocks and dives, net and out, house players | Ported statement by statement |
| Daily skill journey (`SportsJourney`, `CourtPractice`): 30 stages per sport, cycles, partner/opponent choice by aptitude, painted shapes and ordered trails, every drill outcome, 3 lives, streaks | Ported |
| Court renderer (`SportsView`): squash pseudo-3D court with the perspective wood floor, wall questions and answer circles; volleyball camera fitting (perspective portrait, orthographic wide), beach water mesh, park lawn, net, actors sized by visible body with racket and grip, stable name tags with leader lines, ball trail, contact blend and landing ring, reception zoom, HUD, hints, banners, practice targets, celebration | Ported to Core Graphics (static backdrop and squash court pre-rendered per size) and SpriteKit (`SKWarpGeometryGrid` for the 24 x 20 water mesh) |
| Touch grammar: drag to move, wall/floor taps, pro strokes, volleyball taps (210 ms single / 240 ms double tap), swipes up/down/across, net blocks, reception-zoom inverse mapping | Ported |
| Pages (SwiftUI): home with Android `FamilyMenu.organize` sections (Start & learn with the avatar row, Play, Saved games, Advanced, Parent zone link), daily journey, journey list and result with the celebration, Play setup (control, opponent or every volleyball player with skill stars, serve control, teams, arena, ball, team colours), avatar & ranks, settings (control help, squash question settings, reception assistance, sounds), rate/share/feedback, Learn to play, local three-match cup, friends rooms, public tournaments, lobby, results, parent zone (privacy policy, play without questions, learning progress), pause (continue / save for later / finish) | Ported |
| Online rooms (`SportsOnline`): room authority, own-input command channel with acks, 10 s leases and takeover, results, multi-round cups, public tournament listing and browsing (`orderByChild("updatedAt").startAt(now - 15 min).limitToFirst(50)`) | Ported (`SportsOnline.swift` + `FirebaseSportsDatabase.swift`); field names and types match Android so both platforms share rooms; active only when the app's `GoogleService-Info.plist` is bundled |
| Saved match / room snapshot JSON (`SportsCodec`) | Ported with Android's field names and `org.json` defaults |
| Texts: English, Hebrew, Spanish, Arabic, Hindi, Dutch; RTL | `apptext.json` (898 rows, AppText.kt) and `sportstext.json` (SportsText, SquashText, VolleyText, CourtJourneyText), extracted by the audit |
| Sounds (SoundPool at 0.55) and the menu music (0.17) | Ported (AVAudioPlayer); Android's `game_start` serve sound has no file, so it is silent on both |
| Privacy policy pages (6 languages) | Bundled as `privacy-<language>.html`, shown in a WKWebView with JavaScript off |
| Ads, purchases, code redemption, UMP | Not ported (ads are off in both Android apps; no iOS products) |
| "More Minik apps & games" and the family reminders | Not yet on iOS (planned as a shared family module for every iPhone app) |
| Android unit tests | All 83 core tests ported (`SportsEngineTests`, `SportsJourneyTests`, `RefinementTests`); `AdPolicyTest` tests left-out code |
| Android parity | `AndroidParityTests` replays 29 reference traces (whole matches and drills) recorded from the real Kotlin engine, plus 180 journey stages, questions and Kotlin `Random` vectors |

Intentional iOS differences:
- iOS draws in points; Android `dp(n)` is `n` points and Android pixel sizes (sand texture, one-pixel
  grain lines) are converted with the screen scale.
- A `\n` inside a hint starts a new line (Android's `drawText` drops it).
- The pause dialog does not resume a match on its own when the app returns to the foreground.
- Online play shows Android's "Online play needs this app's Firebase registration…" message until
  `GoogleService-Info.plist` is added for the app.

## Android → iOS file map

| Android | iOS |
| --- | --- |
| `core/SportsEngine.kt` | `Sports/Core/SportsEngine.swift` |
| `core/VolleyPlay.kt` | `Sports/Core/VolleyPlay.swift` |
| `core/SportsJourney.kt` | `Sports/Core/SportsJourney.swift` |
| `core/SportsReception.kt` | `Sports/Core/SportsReception.swift` |
| `core/Characters.kt` | `Sports/Core/Characters.swift` (`Character` is `SportsCharacter`) |
| `core/Ranks.kt`, `core/VolleySkills.kt` | `Sports/Core/Ranks.swift`, `Sports/Core/VolleySkills.swift` |
| `core/Learning.kt` | `Sports/Core/Learning.swift` + generated `QuestionFacts.swift` |
| `SportsCodec.kt` | `Sports/Net/SportsCodec.swift` |
| `SportsOnline.kt` | `Sports/Net/SportsOnline.swift`, `SportsDatabase.swift`, `FirebaseSportsDatabase.swift`, `Node.swift` |
| `SportsView.kt`, `SportsArt.kt`, `ArenaCamera.kt`, `StableLabels.kt` | `Sports/Game/SportsView.swift`, `SportsArt.swift`, `ArenaCamera.swift`, `StableLabels.swift` |
| `SportsActivity.kt`, `JourneyCelebration.kt` | `Sports/App/SportsController.swift`, `SportsViews.swift`, `SportsStore.swift` |
| `localization/AppText.kt`, `SportsText.kt`, `SquashText.kt`, `VolleyText.kt`, `CourtJourneyText.kt` | `Sports/Localization/AppText.swift`, `SportsText.swift`, `apptext.json`, `sportstext.json` |
| `assets/art/*`, `res/raw/*`, `assets/privacy/*` | `Sports/Assets.xcassets/Art` (lossless PNG), `Sports/Art/*.json`, `Sports/Audio`, `Sports/Privacy` |

## Checks

- `python Scripts/audit-sports.py` (catalogs, tables, question facts, text pairs, art pixels, audio,
  JSON and privacy pages, Swift line endings): PASS.
- `python Scripts/audit-sports.py --write-catalog --write-facts` regenerates the JSON tables and
  `QuestionFacts.swift` after Android text changes.
- The reference traces in `Tests/SportsTests/android-golden.txt` come from a scratch harness
  (`GoldenSports.kt`) compiled with the Android core outside the Android project; regenerate them
  the same way after Android engine changes.

## Owner actions

1. Firebase (online rooms and public tournaments): in the `minikswish` Firebase project add the iOS
   apps `com.appsbybros.minik.squash` and `com.appsbybros.minik.beachvolley`, then send their
   `GoogleService-Info.plist` files; they are wired into the targets afterwards.
2. App Store Connect: create the two app records before a TestFlight upload (`MinikSquash`,
   `MinikBeachVolley` schemes; `Scripts/appstore-register-bundle-ids.py` already knows both).
