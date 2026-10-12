# iOS privacy policy pages (iPhone and iPad)

Status: written 4 October 2026 from the source in this repository, for owner and legal review. Nothing has been
published. The pages describe only the iPhone and iPad apps. They do not mention any other platform or its store.

All pages are self-contained HTML (UTF-8, LF line endings, inline CSS copied from the existing Multi Ping Pong website
page, no scripts, no external fonts). Each page says "Last updated: 4 October 2026" and names Apps By Bros,
appsbybros.dev@gmail.com. Hebrew and Arabic pages use `dir="rtl"`.

## Which file is for which app

| Page folder (`appstore/privacy/…`) | App (display name) | XcodeGen target | Bundle ID | Languages |
| --- | --- | --- | --- | --- |
| `Minik/` | Minik | `MinikPlus` | `com.appsbybros.minik.plus` | English, Hebrew |
| `MinikEnglish/` | Minik English (home-screen name "Minik") | `MinikPlusEnglish` | `com.appsbybros.minik.plus.english` | English, Hebrew |
| `MinikMath/` | Minik Math (Android Minik Math's web app) | `MinikMath` | `com.appsbybros.minik.math` | English, Hebrew |
| `MinikMathPlus/` | Minik Math Plus (the original iOS math app) | `MinikMathPlus` | `com.appsbybros.minik.math.plus` | English, Hebrew |
| `MinikPingPong/` | Minik Ping Pong | `MinikPingPong` | `com.appsbybros.minik.pingpong` | English, Hebrew |
| `MinikBounce/` | Minik Bounce | `MinikRetroPingPong` | `com.appsbybros.minik.bouncelearn` | English, Hebrew |
| `MultiPingPong/` | Multi Ping Pong | `MinikMultiPingPong` | `com.appsbybros.minik.crosspong` | English, Hebrew, Arabic, Spanish, Hindi, Dutch |
| `Spud/` | Spud (localized names from `Amudu/*.lproj/InfoPlist.strings`) | `MinikAmudu` | `com.appsbybros.minik.spud` | same six |
| `MinikSplash/` | Minik Splash | `MinikSplash` | `com.appsbybros.minik.splash` | same six |

Each page is `appstore/privacy/<App>/<Language>/privacy.html`. `appstore/privacy/index.html` links all 30 pages.

## How the pages were made

### Multi Ping Pong, Spud, Minik Splash (six languages)

Each page starts from that app's existing website page in the same language:
`C:\Projects\MinikCrossPong\website\<Language>\privacy.html`, `C:\Projects\MinikAmudu\website\<Language>\privacy.html`
and `C:\Projects\MinikSplash\website\<Language>\privacy.html`. Section order and headings are unchanged.

- **Copied verbatim:** all section headings, the footer heading and date line, "Your choices and rights", "Contact and
  policy changes", the "On your device" paragraph of Spud and Minik Splash, and the "Online play and sharing" paragraph
  (one sentence added or replaced, see below).
- **Edited:** the intro (now "the iPhone and iPad app"); Multi Ping Pong's "On your device" (the age-category sentence was
  removed and "seen announcements" became "which game results you have already seen", see facts below).
- **Online play:** Multi Ping Pong gets one added sentence; Spud and Minik Splash have their "production online play is
  disabled in the reviewed build" sentence replaced by the same sentence: online play needs this app's Firebase
  registration, the version reviewed for this policy does not include it yet, so rooms are not active, nothing is sent
  to Firebase, and offline play works.
- **Rewritten for iOS:** "Ads and children", "Purchases and codes", "Permissions and speech", "Providers and security",
  "Retention and deletion", and the provider links (Google Privacy Policy, Firebase privacy, Apple Privacy Policy; the
  two AdMob links appear only inside the "if a future version enables ads" paragraph and point to the iOS pages
  `developers.google.com/admob/ios/privacy/data-disclosure` and `developers.google.com/admob/ios/targeting`).
  Rewritten sentences reuse the existing translation of any sentence whose meaning did not change (for example "These
  settings limit targeting; they are not a legal certification." and "Adults should supervise …").

### Minik Math (English and Hebrew, 12 October 2026)

Adapted from the Minik Bounce pages, whose data handling is the closest: a game from bundled files in a web view,
interstitials, Remove Ads behind the grown-up check. Changed: the app description; what is stored on the device;
the website link at the bottom of the home screen, which opens in Safari only after the grown-up check; when ads
show (after a finished round or Ping Pong game, never the first two rounds, at least two minutes apart); the
"Parents · Remove ads" link on the home screen. The earlier Minik Math pages describe the original app and moved
to `MinikMathPlus/`, with the new name.

### Minik, Minik English, Minik Math Plus, Minik Ping Pong, Minik Bounce (English and Hebrew)

Written from the iOS source. Sections: on your device; the app's online part (leaderboard, online services, online play,
or "the game and the internet"); learning reminders (Minik, Minik English, Minik Math Plus); speech/sound and permissions;
ads and children; purchases; children and parents; providers and security; retention and deletion; choices and
rights; contact and changes. The Hebrew pages keep the Latin app names, because these targets do not localize
`CFBundleDisplayName` (`project.yml`).

## Facts each page relies on

Line numbers are from the current working tree.

### Shared by the six Minik apps

- **Ads on in Release.** `project.yml` sets `MINIK_ADS_ENABLED: YES`, `MINIK_ADS_POLICY_APPROVED: YES` and real AdMob IDs
  for MinikPlus (125–128), MinikPlusEnglish (211–214), MinikMathPlus and MinikMath, MinikPingPong (329–332) and
  MinikRetroPingPong (384–387); Debug uses Google's sample app ID, which `MinikAdsConfiguration` treats as "no ads"
  (`Sources/MinikAds.swift:76`, `:82-87`).
- **Ad request flags.** `Sources/MinikAds.swift:64-70` (child-directed, under age of consent, G, no personalization);
  `Sources/GoogleMobileAdsInterstitialService.swift:48-50` (`ageRestrictedTreatment = .child`, max rating G,
  `publisherPrivacyPersonalizationState = .disabled`); same for Minik Ping Pong in `Sources/ModernPong/MPAds.swift:82-83`.
  Google's targeting page confirms `ageRestrictedTreatment` replaces the child-directed and under-age-of-consent tags.
- **Ad timing.** Activities report an opportunity only after a completed word, round, game or match
  (`Sources/MinikActivityHubView.swift:299,306,798,829,844,863,887,903,920,936,950,1253`); the policy waits 60 s after
  launch and keeps at least 3–7 minutes between ads (`Sources/MinikAds.swift:181-184`). Minik Ping Pong: only after a
  completed match, after more than two matches in total and at least two minutes apart
  (`Sources/ModernPong/MPAds.swift:23-25`, `:88-98`). Minik Bounce: after a finished game
  (`Sources/RetroPong/BounceRootView.swift:43-49`).
- **No tracking permission, no advertising identifier.** No `ATTrackingManager`, `AdSupport`, `NSUserTrackingUsageDescription`
  or UMP consent code anywhere in `Sources/`, `MultiPong/`, `Amudu/`, `Splash/` or `project.yml` (repository search).
- **Ad-frequency state is local.** `MinikAdPolicyRepository` (UserDefaults, `Sources/MinikAds.swift:250-277`);
  Minik Ping Pong also stores recent play time (`MPAdPolicy`, `Sources/ModernPong/MPAds.swift:8-28`).
- **Purchases.** StoreKit 2 through `Packages/AppStoreCommerceKit` (`Product.products`, `Transaction.currentEntitlements`,
  `AppStore.sync`, `StoreKitCommerceStore.swift:14-66`); no purchase server; entitlement cached in UserDefaults
  (`Sources/MinikCommerce.swift:42-65`).
- **Grown-up check.** `Sources/ParentalGateView.swift` (addition problem). Gated in Parent Area: purchase, restore, external
  links, leaderboard on/off and record deletion (`Sources/ParentAreaView.swift:430-436, 515-517, 560-590, 626-640, 678-696,
  765-782`); Remove Ads reminder purchase (`Sources/RemoveAdsReminder.swift:168-221`); Minik Ping Pong commerce sheet
  incl. offer-code redemption (`Sources/ModernPong/ModernPongView.swift:76-81, 130, 517-527`); Minik Bounce "For parents"
  (`Sources/RetroPong/BounceRootView.swift:22-27, 51-97`). The Parent Area itself opens without a gate; the pages do not
  claim otherwise.
- **Remove Ads reminder** (Minik, Minik English, Minik Math only): first after 2 days, then at most every 14 days, only while
  ads are active and the product loaded (`Sources/RemoveAdsReminder.swift:49-70`; evaluated in `Sources/RootView.swift:128-136`).
  Minik Ping Pong and Minik Bounce never start the shared ad coordinator / reminder.
- **Local data only in UserDefaults** (no file, iCloud or CloudKit storage in the code); Minik Bounce's web game also uses
  the web view's local storage. No `isExcludedFromBackup`, hence the "device or iCloud backups may keep a copy" sentence.
- **No name field.** The only text fields in `Sources/` are the grown-up check and Ping Pong room codes
  (`Sources/ParentalGateView.swift:70`, `Sources/ModernPong/ModernPongView.swift:126`).
- **Privacy manifests:** `Resources/Privacy/Language`, `ModernPong` declare linked User ID and Gameplay Content for app
  functionality, tracking false; `LocalOnly` (Math, Bounce) declares no collected data.

### Minik and Minik English

- **Firebase products:** Auth, Firestore, App Check (`project.yml:156-167`, `:242-253`); configured at launch when the
  target's plist is present (`Sources/MinikAppDelegate.swift:9`, `Sources/FirebaseRecordsIntegration.swift:44-67`); plists
  in `Config/Firebase/MinikPlus*/` (project `easycallandanswer`, analytics and ads flags false).
- **App Check:** App Attest provider in non-Debug builds (`Sources/FirebaseRecordsIntegration.swift:113-133`).
- **Anonymous sign-in** before every query, write and delete (`Sources/FirebaseRecordsIntegration.swift:226-242`,
  `Sources/RemoteRecords.swift:388-408`).
- **What is written:** `player_id`, `user_name` (= generated alias), optional `avatar_id`, `score`,
  `correct_answers_in_row`, `app_id` "3", server timestamp `date_achived` (`Sources/RemoteRecords.swift:702-741`);
  private `leaderboard_owners/{player_id}` with `owner_uid` (`Sources/FirebaseRecordsIntegration.swift:178-185`).
  Collections: `score_records` (Minik), `score_records_english_only` (Minik English), shared `correct_answers_in_row`
  (`Sources/RemoteRecords.swift:418-437`).
- **Alias:** four choices from fixed adjective/noun/1–99 lists, optional symbol avatar (`Sources/PublicLeaderboardPrivacy.swift:4-167`);
  participation defaults to on (`:169-170`); nothing is written before an alias is chosen, but the Top 20 lists may be
  read to decide whether to offer an alias (`Sources/RemoteRecords.swift:100-161`) and when the Top 20 screen opens
  (`Sources/RecordsLeaderboardView.swift:27,48`).
- **Parent controls:** switch, alias change, delete while off (`Sources/ParentAreaView.swift:427-531`); deletion removes the
  participant's score and streak documents only (`Sources/RemoteRecords.swift:609-632`); the participant ID lives in
  UserDefaults (`Sources/RemoteRecords.swift:258-302`), so it is lost when the app is deleted.
- **Reminders:** off by default, permission asked only from the Parent Area switch, one repeating local notification a
  week, "Time for Minik" (`Sources/LearningReminderNotifications.swift:85-108, 167-199`); no push entitlement.
- **Speech:** `AVSpeechSynthesizer` (`Sources/LearningSpeech.swift`, `Sources/InterfaceSpeech.swift`,
  `Sources/TicTacToeFeedbackPlayer.swift`); no microphone, camera, contacts, photo or location API in the code.
- **Local data:** progress statistics (`Sources/ActivityProgress.swift:196-231`), points and streaks (`Sources/Rewards.swift:19-29`),
  settings keys listed under `minik.*` in `Sources/`.

### Minik Math (Android Minik Math's web app)

- No Firebase dependency (`project.yml`, target `MinikMath`); the product variant is the Math variant only for its
  separate local purchase and ad state.
- The web view loads only the bundled files and cancels any other navigation; an http(s) link (the footer's main
  site link) opens in Safari only after the grown-up check (`Sources/MinikMathWeb/MinikMathWebView.swift`,
  `Sources/MinikMathWeb/MinikMathWebRootView.swift`). No `fetch`, `XMLHttpRequest`, WebSocket or `speechSynthesis`
  in `Resources/MinikMathWeb`.
- Local data in the web app's storage: `minikMathPracticeLevel`, `minik_last_completed_math_round`,
  `minik_last_completed_pong_match`, `minik.pong.progress.v1` (points, levels and Ping Pong settings); the native
  ad schedule `minik.math.ads.schedule.v1` and the Remove Ads cache.
- Ads: Android Minik Math's AdPolicy (`Sources/MinikMathWeb/MinikMathAdPolicy.swift`) with the shared request flags.
- No reminders and no speech synthesis.

### Minik Math Plus

- No Firebase dependency (`project.yml:301-305`); `RemoteRecordsConfiguration` returns nil for Math, the trophy is hidden
  (`Sources/RemoteRecords.swift:434`, `Sources/MinikActivityHubView.swift:437-447`).
- Ping pong inside Math: Modern Simple (no online repository without `MINIK_PING_PONG`, `Sources/ModernPong/MPController.swift:56-61`)
  and the Retro web game from bundled files (`Sources/RetroPong/MathPingPongChooser.swift:15-16`).
- Speech: `InterfaceSpeechPlayer` in the Math views (for example `Sources/MathCardsView.swift:6,106`).
- Reminders, ads, purchases, grown-up check: shared facts above.

### Minik Ping Pong

- Firebase Auth + Realtime Database, named app, project `minikswish`, root `minikPingPong`
  (`Sources/ModernPong/MPRepository.swift:131-150`; plist `Config/Firebase/MinikPingPong/GoogleService-Info.plist`).
- At start the app signs in anonymously and, for a new ID, registers a generated nickname with avatar and character
  (`Sources/ModernPong/MPController.swift:67-80`; `MPRepository.swift:164-176`, nickname lists in `MPPreferences.swift:3-20`).
- Stored online: `nicknames/`, `profiles/`, `openSlots/`, room records (code, host, settings, participants, matches,
  connections, state, timestamps, knockout rounds; `Sources/ModernPong/MPMultiplayerModels.swift:128-140`),
  `live/<match>/checkpoint|actions` (`MPRepository.swift:236-255`).
- Cleanup: on connect, rooms inactive ≥ 14 days with nobody connected are deleted with their live data
  (`MPRepository.swift:268-287`, called from `MPController.swift:212-214`); profiles/nicknames are not touched.
  Finishing a friendly game or deleting a tournament removes it; leaving a tournament updates it (`MPRepository.swift:256-267`).
- Single games and practice are local engines (`Sources/ModernPong/MPController.swift:248-257`). No speech code.

### Minik Bounce

- Product variant is the Ping Pong variant but there is no Firebase dependency (`project.yml:392-396`).
- Web view loads only bundled files and cancels any other navigation (`Sources/RetroPong/RetroPongView.swift:96-110, 152-155`);
  no `fetch`, `XMLHttpRequest`, WebSocket or `speechSynthesis` in `Resources/RetroPong/*.js`; the footer link is hidden
  (`Resources/RetroPong/ios-host.css:4`).
- Local progress (`Sources/RetroPong/RetroPongStorage.swift:3-16`) and the last finished game score
  (`Resources/RetroPong/app.js:1594`).

### Multi Ping Pong

- No ads: `MPAds.interstitialUnit` always returns nil, so the ads SDK is never started from `MultiPong/`
  (`MultiPong/MPAds.swift:48-53`, `:64-73`). Recent play time is still saved locally (`MultiPong/MPAds.swift:55`,
  `MultiPong/MPController.swift:546`).
- No age selection anywhere in `MultiPong/` (search), so the source page's age-group ad rule was dropped; the dormant ad code
  would mark every request child-directed.
- No purchase UI (`MultiPong/ModernPongView.swift:5,11`). But the shared `RootView` starts the commerce controller for every
  target (`Sources/RootView.swift:74`), and this target has a product ID (`project.yml:434`), so at launch the app asks
  StoreKit for that product and current entitlements. The page says so.
- Online code: root `minikCrossPong`, only with a plist for this bundle ID and project `minikswish`
  (`MultiPong/MPRepository.swift:213-232`); no such plist exists in `Config/Firebase/` or the target resources, so the
  local repository is used (`docs/multi-pong-ios-handoff.md`, "Partial").
- Data synchronized and the 14-day cleanup are the same code paths as Minik Ping Pong (`MultiPong/MPRepository.swift:242-372`).
- No speech code (no `AVSpeechSynthesizer` in `MultiPong/`).

### Spud

- No ads or StoreKit dependency (`project.yml:498-502`; `docs/amudu-ios-handoff.md`, "Not ported").
- Online rooms only with a bundled plist for this bundle ID with a database URL (`Amudu/Online/OnlineRoom.swift:21-40`); none
  is bundled. No room expiry or cleanup code in `Amudu/Online/`.
- Speech: names, the stop call, renamed nicknames and preset phrases via `AVSpeechSynthesizer`
  (`Amudu/UI/AppModel.swift:334-352`, `Amudu/Game/GameAudio.swift:53-60`).
- Local data: UserDefaults `amudu.*` (`Amudu/UI/AppModel.swift:50-62`).

### Minik Splash

- No ads or StoreKit dependency (`project.yml:552-556`; `docs/splash-ios-handoff.md`).
- Online only when `GoogleService-Info.plist` is bundled; none is. Learning profile written to `profiles/<uid>` when online
  (`Splash/Net/OnlineSession.swift:184-186`). No room expiry code.
- Speech: question read aloud when the ♫ control is tapped (`Splash/Game/SplashArenaView.swift:1071`,
  `Splash/Game/SplashAudio.swift:121-136`).

## Could not verify / owner decisions

1. **Nothing was built or run.** This Windows machine has no Swift toolchain; every fact comes from reading source and
   configuration. Runtime behavior (network traffic, prompts, StoreKit, ads) is unverified.
2. **Firebase registration for Multi Ping Pong, Spud and Minik Splash.** The pages state that the reviewed version does
   not include it. If a `GoogleService-Info.plist` is added before release, replace that sentence in all 18 pages and
   review the online paragraphs again (Minik Ping Pong's page shows the "connects at start" wording to reuse).
3. **Google Mobile Ads SDK linked but unused in Multi Ping Pong** (`project.yml:447-448`), with Google's sample app ID in
   `GADApplicationIdentifier`. App code never starts it; whether the linked SDK does any network work on its own was not
   verified.
4. **StoreKit lookup in Multi Ping Pong** for `remove_ads_multipingpong` at launch. If the owner removes the product ID or
   the commerce start for this target, delete the "Even now…" paragraph (six languages).
5. **Older repository docs disagree with `project.yml`.** `docs/app-store-privacy-data-inventory.md`,
   `docs/apple-release-checklist.md` and `docs/privacy-policy-website-replacement.md` say ads are disabled in Release
   (including Minik Ping Pong). The current `project.yml` enables them with real IDs; the pages follow `project.yml`.
6. **Leaderboard security rules.** `docs/firebase-leaderboard-contract.md` says the strict Firestore rules that use
   `leaderboard_owners` are not deployed yet. The pages therefore say the private link is "intended" to let only that
   identity change the records. App Check enforcement is off per the same document.
7. **Anonymous Firebase identity after deleting an app.** Firebase Auth may keep its user in the Keychain; the pages say
   only that the app "may no longer be able to find" online data after deletion.
8. **Launch-time Firebase traffic in Minik and Minik English** (App Check token refresh, Firestore) before any leaderboard
   use was not verified; the pages make no claim about it.
9. **Exact data processed by Google AdMob** follows Google's own disclosure; the pages use the general list (IP address,
   approximate location, interactions, diagnostics, device information).
10. **Speech voices** are Apple's on-device `AVSpeechSynthesizer` voices; whether a given device downloads a voice is
    managed by iOS, not by the apps.
11. **Legal items** still need the owner/legal reviewer: controller identity and address, child-specific legal bases per
    territory, Kids Category choices, retention periods and deletion turnaround, cross-border wording.
12. **Hosting.** The pages are not published. The apps' in-app privacy link is still `https://miniklearn.com/privacy`
    (`project.yml:44`, used by Parent Area); App Store Connect privacy URLs must be set by the owner.
13. **App names.** Minik English shows "Minik" on the home screen (`project.yml` `CFBundleDisplayName`); the page title uses
    "Minik English" as in `appstore/screenshots.json`.
    The Hebrew Multi Ping Pong and Minik Splash pages keep the source pages' Hebrew names (מולטי פינג פונג, מיניק ספלאש),
    although those two iOS targets show the English name on the home screen; Spud's names match `Amudu/*.lproj`.

## Checks run

- Search across `appstore/privacy/**` (all languages, case-insensitive) for the other mobile platform's name in Latin,
  Hebrew, Arabic and Hindi script, its store, billing, integrity and services names, the consent-SDK name, "consent form",
  "storage controls" and "uninstall": **0 hits** (exact terms are listed in the task report).
- HTML check of all 29 files: doctype, UTF-8 meta, no BOM, LF only, final newline, balanced tags, `lang`/`dir` per
  language, no scripts or external styles, all relative links resolve, all external links HTTPS.
