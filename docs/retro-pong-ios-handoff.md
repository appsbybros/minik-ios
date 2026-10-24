# Shared 80’s STYLE Pong — 2026-09-28

## 2026-10-24 sync

iOS now matches Android Bounce `c21200d` (`C:\Projects\MinikPaddleAndLearn`). The only production change since `506490e` is `4f38dd5` ("Add parent-only rating, sharing and feedback to Bounce"); `3422332` and `c21200d` only raise the Android version.

Ported:
- Parents page (`BounceRootView`, after the same grown-up gate as Remove Ads, as Android's `MonetizationActivity` shows its options only after its adult gate): a bold "Remove ads" heading above the purchase text, then "More ways to support Minik Bounce" with "Rate Minik Bounce & Learn", "Share Minik Bounce & Learn" and "Send feedback", in Android's English and Hebrew wording. The page now scrolls.
- Rate: Android opens the Play listing; Minik Bounce has no App Store id or link yet, so iOS asks for the App Store rating prompt (`MinikAppFeedback.requestReview()`), as the other iPhone ports do. Android's "Google Play is not available" toast has no iOS counterpart.
- Share: the system share sheet (`MinikShareSheet`) with Android's share text and, in place of the Play listing, the app's page `https://miniklearn.com/apps/minik-bounce-and-learn/` (the family catalogue's landing page for `bounce`).
- Feedback: `mailto:appsbybros.dev@gmail.com` with Android's localized subject; when no mail app opens, the address is copied and Android's "No email app found. The feedback address was copied." shows on the page.
- "For parents" on the setup (`ios-host.js`, Android `minik-monetization.js`): now a link (`<a role="button">`, label "For parents") centred in the measured gap between the setup body and Start; when the gap is too small it moves onto its own row under the setup title. iOS also falls back that way if a setup part is missing.

Checks: 16 host tests and the engine test pass; `audit-retro-pong.py` passes 209 checks; the Windows iOS type check reports 0 errors for MinikRetroPingPong, MinikMathPlus and MinikMultiPingPong.

## 2026-10-13 sync

iOS now matches Android Bounce `506490e` ("Refresh Bounce menus, family messages and current store package", `C:\Projects\MinikPaddleAndLearn`). The web delta since `0f5b85f` is `maze-sky.css`, its link in `index.html` and the family hooks in `minik-monetization.js`; everything else in that commit is Android build, billing or store material.

Ported:
- `maze-sky.css` (new): Maze-style raised buttons and panels, centered landscape forms and white text fields. Direct copy with LF line endings; `index.html` links it after `pong-layout.css`, as on Android, and `ios-host.css` stays last. Imported by `tools/bounce-refresh/sync-ios.py`; `docs/retro-pong-android-provenance.json` now has 77 entries.
- Family messages, which Android Bounce now hosts (shared `Family/` code, unchanged): at one eligible ad break in 30 (at most once a day) the card for another Minik app replaces the interstitial, and the game's result shows when the card closes; the remove-ads reminder on the idle setup ("Remove ads" opens the parents page behind its grown-up gate); "More Minik apps & games" first on the parents page. `ios-host.js` sends Android's `menuIdle` signal every second while the setup with "For parents" is idle on screen; `RetroPongView(onMenuIdle:)` passes it to `BounceRootView`. The target bundles the family catalogue and art and sets `MinikFamilyCatalogKey: bounce`.
- The "For parents" link colour (`#3F8CFF`) already matched.

Deliberate differences:
- Android Bounce is landscape-only. In iOS portrait the setup is a full-screen page, so `ios-host.css` drops maze-sky's raised-card shadow there.
- "More Minik apps & games" is a quiet link (`FamilyMenuLink`), not a button, as in every iOS app.
- Math Plus's Bounce gets the new styles but no family messages: it has no parents link, so it never sends `menuIdle`, and its ads stay Math's.

Skipped: Play Store packages and screenshots, versionCode/versionName, Gradle source sets, the `BounceSkyCaptureTest` device capture, and Android's billing tweak (ownership counts as resolved only once known), which iOS `MinikCommerceController.ownershipResolved` already does.

Checks: 15 host tests and 16 engine checks pass; `audit-retro-pong.py` passes 207 checks. Not compiled (no Swift toolchain here).

**Android sync — 2026-10-07:** the web payload in `Resources/RetroPong` now matches Android Bounce `0f5b85f` ("Polish Pong HUD across mobile and large windows", `C:\Projects\MinikPaddleAndLearn\app\src\main\assets\www`). That commit changed `app.js`, `pong-extras.js` and `pong-layout.css`. iOS already had its `app.js` and `pong-extras.js`: the 2026-10-02 sync took them from the then uncommitted Android files. So only `pong-layout.css` was re-imported, the same way as before: a direct copy with its line endings normalized to LF (Android now commits this file with CRLF), without an iOS adaptation. The new rules apply to the native inset host (`minik-android-inset-host`, which the iOS host also gets through `MinikNativeInsets/1`). They give the desktop court layout (`pong-desktop-active`) a readable, correctly ordered total score, and hide the site footer. On iOS no visible change is expected: the adapted `app.js` treats every iOS device as mobile, so the desktop layout never turns on, and `ios-host.css` already hides the footer. The file's two hashes are updated in `docs/retro-pong-android-provenance.json` (76 entries). Every other Android `www` file still matches its recorded hash; `minik-monetization.js` and `README.md` stay out on purpose. Math's Ping Pong loads the same folder, so it gets the same rules.

**Ads update — 2026-10-01:** as on Android Bounce, the standalone app (`BounceRootView`) now shows an interstitial after a finished game and a "For parents" link on setup that opens the grown-up gate before Remove Ads and Restore. `ios-host.js` implements Android's `MinikMonetization` contract; inside Math, a finished Bounce game is a Math ad opportunity and no parents link is shown. The ad-free statements below describe the earlier implementation.

**Latest branding/navigation update:** [Minik Bounce & Learn — 2026-09-30](bounce-refresh-2026-09-30.md). The standalone icon/display name, Android reference path, and Back behavior below describe the earlier implementation; the September 30 report supersedes those parts.

Implemented in source. Windows gameplay/bridge checks pass. **No Xcode build, IPA, iOS simulator run, or physical-device verification has been performed in this task.**

## Repository and commits

- Writable iOS worktree: `C:\Projects\Minik-to-IOS\ios-main-merge`, branch `main`.
- Git repository: `C:\Projects\Minik-to-IOS\ios\.git`; remote `https://github.com/appsbybros/MinikPlus-iOS.git`.
- The moved worktree’s obsolete Git link was repaired with `git worktree repair`.
- Modern implementation committed locally as `b15717f` (`Port Modern Ping Pong to shared native iOS Full and Simple modes`).
- This 80’s implementation is the following local commit (`Share current Android 80s Pong gameplay across iOS Math and standalone`). The user will push. No push or workflow dispatch was made.
- Android reference: `C:\Projects\minik80sPingPong\app\src\main\assets\www`, read-only. Modern Android project also unchanged. No Firebase/rules/TripleShot mutation or attached Pixel/ADB access.
- The pre-existing reference ZIP and oversized rollout file remain untracked and excluded from commits.

## One game, two entry points

The current Android 80’s game itself is an HTML/Canvas/WebView implementation. Reusing its current payload avoids translating its timing, hit boxes, rank progression and responsive layout into a second engine. The iOS layer is a native SwiftUI/WKWebView host with a small lifecycle, storage, local-menu-music and navigation bridge. It loads bundled files offline; remote navigation and network connections are blocked.

| Launch | Behavior |
| --- | --- |
| Existing `MinikPingPong` scheme | Native Modern, Full experience; unchanged by this unit |
| `MinikMath` → Ping Pong → MODERN | Shared native Modern, Simple experience; choose a house player and Standard/Pro; completion/exit returns to Math |
| `MinikMath` → Ping Pong → 80’s STYLE | Updated shared Retro game; Back exits to Math |
| New `MinikRetroPingPong` scheme | Directly opens the same Retro setup/game; its Back stops the game and shows the existing Play again panel, because iOS apps do not quit themselves |

`RetroPongView(onExit:)` has **no feature-mode parameter**. `onExit` only lets an embedding app dismiss it. The entire game/help/settings/features are the same in both hosts. No second copy of its engine is maintained. Another host must include `Sources/RetroPong/RetroPongView.swift`, `RetroPongStorage.swift` and the `Resources/RetroPong` folder resource. `MathPingPongChooser` is only the Math navigation wrapper.

New standalone development bundle ID: `com.appsbybros.minik.bouncelearn`; display name `Minik Bounce` (matches Android `com.appsbybros.minik.bouncelearn`). Existing bundle IDs are unchanged. Apple Developer/App Store Connect registration and signing for the new app still need owner setup before distribution. No Firebase registration is needed for Retro.

## Imported behavior

- Current Android gameplay, Balloon Madness objects and cooldowns, arithmetic train, cumulative points, settings/help, mobile arrows plus swipe, and countdown/replay behavior.
- A new user starts at **Beginner**. Difficulty, match target, Balloon Madness, arithmetic operation/levels and cumulative points are saved and restored.
- Opponent values match Android exactly:

| Level | Movement/frame | Slow movement/frame | Slow rally chance | Reaction frames | Intentional miss chance | Miss offset |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Beginner | 3.45 | 2.75 | 42% | 6 | 30% | 220 |
| Medium | 4.30 | 3.75 | 15% | 3 | 10% | 130 |
| Hard | 5.10 | 5.10 | 0% | 1 | 0% | 0 |

Hard still has limited movement and must physically reach the ball. Those are the existing **80’s** profiles, not Modern’s four-level profiles.

Rank thresholds are `0,100,200,300,500,700,900,1200`. Rank `r = 0...7` uses paddle length factor `2.5 − 2r/7` and player movement factor `1 + 0.04r`, with the reference’s viewport clamps. Both paddles always use the same final computed length. Yellow is widest; silver/gold narrowest. Arrows and the player paddle show the highest unlocked rank; they do not randomly downgrade between games.

The train starts after five active seconds and returns 15 active seconds after exit. It accepts **one tap answer**; correct gives +3 cumulative points and raises the current arithmetic level, wrong lowers that level, bounded to 1...12. Neither changes the match score. Ball collisions never choose an answer. With Balloon Madness off the ball passes through; with it on the entire train rebounds it with a contact lock. Train arrival slows/freezes the world over the reference progress interval .03...28; the train retains 30% pace at maximum slowdown. After an answer the world eases back over 3.2 seconds, including if the train leaves during recovery. Backgrounding pauses the clocks.

The setup opens first; Help is optional. Start uses the full court-centered 3–2–1 countdown. Replay starts directly using saved settings. Current English/Hebrew help, Back behavior, total score/header spacing, wider arrows, responsive landscape controls and full-width train across arrow gutters are retained. WKWebView occupies the native safe area; its dark background extends behind system edges without adding a second notch inset.

## Audio and ads

| Event | Asset |
| --- | --- |
| Player paddle | `minik_kick` |
| Minik paddle | `minik_kick2` |
| Player Pong point | `success_sound` |
| Minik Pong point | `failure_sound` |
| Correct train tap | `success_in_a_raw_sound` |
| Wrong train tap | `failure_answer_sound` |
| Balloon explosion | `balloon_explode` |
| Beach/cotton ball | `ball_hit` |
| Car | `car_hit` |
| Train collision | `train_hit` |
| Train entry, once per visit | `train_horn` |
| Countdown finished, once | `game_start` |
| Pre-game menu, matching Android host calls | `cool_music2`, one native loop |

Audio bank and MP3/WebP assets are the reference bytes. Effects remain event-driven, with existing overlap guards. Background, navigation and destruction stop appropriate audio; the menu loop is paused/resumed by lifecycle and never plays under a running match. Clouds retain their reference behavior. The reference's unused `splash.mp3` is retained in the copied payload; no Retro event uses it.

**No ads, purchase flow, Firebase, or monetization opportunities were added to Retro.** The prior Modern implementation already included Debug test ads and StoreKit UI; it is unchanged, with production ads disabled. Math’s former legacy Pong completion-to-ad callback is no longer used by these new routes. A common advertising library remains future work.

## Storage and integration boundaries

The web game retains `minik.pong.progress.v1`. Only that key is mirrored to native UserDefaults `minik.retro-pong.progress.v1`, protecting it across WebKit file-origin/install-location changes. Incoming state is validated for schema/version, bounds and size. Math curriculum, settings, progress and other web-storage keys are untouched.

If no new Retro state exists, explicitly saved legacy iOS difficulty and per-difficulty target are imported; old target 10 maps to supported 11. Unset/unknown difficulty starts at Beginner. Legacy keys are left intact. Cumulative points were not part of the retired Swift Pong preference contract. Separate installed apps keep separate app-local progress; this change does not introduce cross-app/cloud syncing.

On background/foreground the bridge pauses/resumes gameplay and adjusts existing deadlines. On WebKit process eviction it reloads setup from the latest native progress; an unfinished rally is not restored and no result is invented. Exit stops timers/audio and removes the native handler on dismantle. Only bundled main-frame messages and file navigation are accepted.

## Exact changes and allowed payload differences

Full file inventory and working-tree hashes: `docs/retro-pong-changes.json`. Every copied Android source/asset and its original hash: `docs/retro-pong-android-provenance.json` (73 entries). Output provenance hashes normalize text line endings so checks also work after a macOS Git checkout; binary asset hashes remain exact.

- Direct import: all images/audio, audio bank/engine, base CSS/layout. Text line endings are normalized by the tooling.
- `app.js`, `pong-extras.js`: extend Android-native capability recognition to the iOS native host. Also accept host language and treat native iPads as mobile devices.
- `index.html`: load `ios-host.js`/`ios-host.css` and add the offline content-security policy.
- Added native host/storage, Math chooser, standalone icon catalog, host/test files, provenance/check script and manual Apple workflow.
- Carefully merged `MinikActivityHubView.swift`, `MinikApp.swift`, `project.yml` and release audit/docs. Existing educational engines and Modern implementation are unchanged.
- Old native Pong source/tests/assets remain for compatibility/history; they are no longer used by Math/standalone Pong entry points.

## Validation

From the iOS root:

```powershell
node Tests/RetroPong/engine.test.cjs
node --test Tests/RetroPong/host.test.cjs
python Scripts/audit-retro-pong.py
python Scripts/audit-modern-pong.py
powershell -NoProfile -File Scripts/audit-release-configuration.ps1
powershell -NoProfile -File Scripts/audit-minik-ads.ps1
powershell -NoProfile -File Scripts/audit-minik-commerce.ps1
powershell -NoProfile -File Scripts/audit-product-configuration-tests.ps1
```

Results: 16 game checks + 7 JavaScript host tests pass; 191 Retro source/asset checks and 152 existing Modern checks pass; all four PowerShell audits pass. Six added/changed Swift files parse without grammar errors. Seven new native XCTest cases are authored but **not run**. Logs: `docs/retro-pong-evidence/windows-checks.json`. The JavaScript tests exercise the actual imported payload under an iOS native user agent; they do not replace WebKit/device testing.

Browser discovery returned no available browser, so no visual preview/screenshots were obtained. No attached Android devices were touched. No macOS/Xcode is available here: there is **no compiled iOS build or IPA** from this task.

After pushing, manually run **Retro Pong Simulator Verification** (`.github/workflows/retro-pong-simulator.yml`). It runs the portable checks, generates the Xcode project, builds Retro and Math, runs ProductConfigurationTests, and captures initial English/Hebrew Retro simulator screenshots. It was not dispatched here. The existing four-product workflow remains unchanged.

## Apple follow-up checklist

1. Run the manual workflow; inspect builds, XCTest results and initial screenshots rather than treating source checks as Apple approval.
2. Small/normal iPhone and iPad: English/Hebrew portrait and landscape setup/help, Start spacing, safe areas, 3–2–1 centering, gameplay controls, totals, full-width train with no black gutters/clipping.
3. Math → each game → Back; Modern Simple match completion returns to Math; repeated entry/exit preserves Math progress and does not duplicate audio.
4. Retro Beginner default then persisted Medium/Hard; match target/Madness/operation persist. Award points, relaunch, confirm ranks/colors and equal player/Minik paddle lengths across rotation.
5. Arrow holds plus paddle swipe; first train, wrong/correct taps, no duplicate points; ball passes through when Madness off and rebounds without answering when on; slowdown/recovery and recurrence.
6. Every listed audio event, one horn/countdown cue per event, sustained object overlap, menu music stops on Start/exit and pauses in background.
7. Background during countdown/rally/train/help; return without time jumps; WebKit process recovery; standalone Back/Play again.
8. Confirm Retro remains ad-free. Modern’s separate outstanding live multiplayer/StoreKit/ads checks are listed in its own handoff.
