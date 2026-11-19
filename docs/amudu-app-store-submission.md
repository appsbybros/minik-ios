# Minik Spud (Minik Amudu) — App Store submission

Prepared 19 November 2026 for the first App Store release of the `MinikAmudu` target (bundle ID
`com.appsbybros.minik.spud`, version 1.0). Everything below is ready to paste into App Store Connect. Nothing was
uploaded, submitted or deployed. Facts come from reading the code; nothing was built or run.

## 1. What is ready in the repositories

| What | Where |
| --- | --- |
| Store texts in six App Store languages (name, subtitle, promotional text, description, keywords, privacy, marketing and support URLs) | `appstore/metadata/MinikAmudu/{en-US,he,es-ES,ar-SA,hi,nl-NL}/` |
| iOS privacy policy, six languages | `appstore/privacy/Spud/<Language>/privacy.html` |
| The same policy inside the app (shows the home menu's "Privacy policy" button under "Advanced") | `Amudu/Privacy/privacy-{en,he,es,ar,hi,nl}.html` |
| Website copies (not deployed) | `C:\Projects\MinikLearnWebsite\latest_code\preview\minik\apps\amodu\privacy-ios.html` and `privacy-ios\{en,he,es,ar,hi,nl}.html` |

`python3 Scripts/appstore-metadata.py --check-only --apps MinikAmudu` passes (all lengths inside App Store Connect's
limits). The "App Store metadata" workflow (`apps: MinikAmudu`, dry run first) can fill the texts once the app record
exists; it never submits for review.

Store names per language (from Android's `app_name`, as in `Amudu/*.lproj/InfoPlist.strings`): en-US "Minik Spud",
he "מיניק עמודו", es-ES "Minik Pies Quietos!", ar-SA "مينيك لعبة أسماء", hi "Minik Naam Aur Ball", nl-NL "Minik Stand in
de mand". The privacy URL is the app's own iOS page, `https://miniklearn.com/apps/amodu/privacy-ios.html?lang=<code>`
(before, `https://miniklearn.com/privacy`, the website's general policy, which does not cover Spud). The marketing URL is
`https://miniklearn.com/apps/amodu/?lang=<code>`; support stays `https://miniklearn.com/contact`.

## 2. Steps only the owner can do

1. **Agreements:** accept the Paid Apps Agreement and complete tax and banking in App Store Connect (needed for any
   in-app purchase, even in a free app). Declare the EU Digital Services Act trader status.
2. **App record:** create the app (iOS, primary language English (U.S.), bundle ID `com.appsbybros.minik.spud`, SKU of
   your choice). If "Minik Spud" is already taken as an App Store name, change `en-US/name.txt` before running the
   workflow.
3. **In-app purchase:** create a **Non-Consumable** with product ID `com.appsbybros.minik.spud.full_game` (must match
   `SPUD_FULL_GAME_PRODUCT_IDENTIFIER` in `project.yml`), reference name e.g. "Spud full game", choose the price, turn
   **Family Sharing on** (it cannot be turned off later), add the six localizations from section 3, the review
   screenshot (the unlock screen) and the review note from section 3. Availability: all countries where the app is sold.
   Attach it to version 1.0 on the version page ("In-App Purchases and Subscriptions") so it is reviewed with the app.
4. **Firebase:** in Firebase project `minikswish`, add an iOS app with bundle ID `com.appsbybros.minik.spud`, download its
   `GoogleService-Info.plist` and put it at `Config/Firebase/MinikAmudu/GoogleService-Info.plist` (`project.yml` already
   bundles it when present; without it online shows "Online activation is pending."). Anonymous sign-in and the
   `minikAmudu/...` Realtime Database rules are shared with Android. Check in the Firebase console that **App Check is
   not enforced for Realtime Database** (the iOS target links no App Check; Android uses App Check only for its separate
   access-code app), or online play will fail on iOS.
5. **Website:** deploy the updated `minik/apps/amodu/privacy-ios*` pages before submitting, because App Review opens the
   privacy URL. `FULL.zip` / `PATCH.zip` in `latest_code` were not rebuilt.
6. **Build:** Xcode 27 or later; upload through `testflight.yml` / `public-export/release_ios.py` when you choose.
7. **Screenshots:** the "App Store screenshots" workflow already has a `MinikAmudu` set in six languages
   (`appstore/screenshots.json`); App Store captures count as owning the full game, so locks do not show.
8. Fill in the App Store Connect forms with sections 4-8 and press "Add for Review" yourself.

## 3. In-app purchase localizations

Product `com.appsbybros.minik.spud.full_game`. Display name at most 30 characters, description at most 45.

| Locale | Display name | Description |
| --- | --- | --- |
| English (U.S.) `en-US` | Full Game | 10 players, every arena, ball and challenge |
| Hebrew `he` | המשחק המלא | עד 10 שחקנים, כל הזירות, הכדורים והאתגרים |
| Spanish (Spain) `es-ES` | Juego completo | 10 jugadores, escenarios, pelotas y retos |
| Arabic `ar-SA` | اللعبة الكاملة | حتى 10 لاعبين وكل الساحات والكرات والتحديات |
| Hindi `hi` | पूरा गेम | 10 खिलाड़ी, सारे मैदान, गेंदें और चुनौतियाँ |
| Dutch `nl-NL` | Volledig spel | 10 spelers, alle velden, ballen, uitdagingen |

The names match the in-app button "Unlock the full game" (`Amudu/Store/StoreText.swift`).

IAP review note (English):

```
One-time, non-consumable unlock of the full game (Family Sharing on). Without it: up to 3 players, the Sunshine park
arena, the Soft foam and Beach ball balls, the paint balloon for 3 welcome games and then one game a day, and the first
7 challenges. With it: up to 10 players, all three arenas, all five balls, paint balloons any time and every challenge.
To reach it: Home > Play > Create game > tap any choice marked with a lock (e.g. Room capacity 4, Tropical beach or
Neon party) > "Unlock the full game · <price>" > answer the grown-up multiplication question. Restore purchases is on
the same screen.
```

## 4. App Review notes (App Review Information > Notes)

Sign-in required: **No** (leave the demo account empty). Contact: Apps By Bros, appsbybros.dev@gmail.com.

```
Minik Spud is a playground ball game for the whole family (children playing with parents, siblings and friends). A name
is called, the ball goes up, the called player catches it and throws a soft ball at a running player, who can catch,
jump or duck. Being hit only adds a penalty letter or a funny nickname; nobody is hurt and there is no violence. It is
not in the Kids category. All characters, art, sounds and texts are our own.

No login or account is needed. Everything except online rooms works offline.

FREE TIER AND THE ONE PURCHASE
The app is free to start. One non-consumable in-app purchase, "Full Game" (com.appsbybros.minik.spud.full_game, Family
Sharing on), unlocks everything. Without it: up to 3 players in a game, the Sunshine park arena, the Soft foam and Beach
ball balls, the paint balloon for 3 welcome games and then one game a day, and the first 7 challenges of the learning
journey. Locked choices stay visible with a lock and open the unlock screen. Apple's in-app purchase is the only
payment method; there are no subscriptions, no access codes and no links to outside payment. The free tier, the price
and the features are the same in every country.

HOW TO REACH THE PURCHASE
1. On the home screen, under "Play", tap "Create game".
2. Tap any locked choice: Room capacity 4 (or more), the "Tropical beach" or "Andromeda" arena, or the "Neon party" or
   "Tennis ball" ball. The "Unlock the full game" screen opens.
3. Tap "Unlock the full game · <price>". A grown-up check asks a multiplication question (for example 6 × 7); type the
   answer and confirm. The App Store purchase sheet appears.
Another way: Home > "Advanced" (tap the section to open it) > "Settings & feedback" > answer the grown-up question >
"Full game: not unlocked yet" > the same unlock screen. "Restore purchases" is on the unlock screen and needs no check.
The grown-up check also protects Settings & feedback and every link that leaves the app (privacy policy links, "More
Minik apps & games").

ONLINE PLAY (PRIVATE ROOMS AND FAMILY LEAGUES ONLY)
Online play is only for people who already know each other. A room is joined only by typing its six-character code,
which the host shares outside the app (in person or through their own messaging). There is no public matchmaking, no
lobby list, no friend search, no player profiles and no open chat, so the app creates no contact between strangers.
Inside a room players can send six fixed preset phrases (for example "Nice catch!"), and in the nickname game they may
type one-word nickname suggestions (letters and digits only, at most 24 characters, no spaces or links), seen only by
the players in that room during a short vote. Player names are limited to 22 letters, digits, spaces, hyphens and
apostrophes; the database rules reject anything else. A family league is the same private group with a fixed
invitation code. Firebase anonymous authentication gives each device a random ID; no email, phone or real name is asked.
Online play needs a player name: first type any name in the name field on the home screen (under "Start & learn").
To try online with one device: Create game > choose at least one house player > "Open private room" > start the game
with the house players. To try two devices: open a room on one, then Home > "Join by code" on the other.

PRIVACY
No ads, no ad SDK, no analytics or crash SDK, no tracking and no App Tracking Transparency prompt. The app uses Firebase
Authentication (anonymous) and Realtime Database only for private rooms, family leagues, an optional 10-minute
lag diagnosis that an adult starts in Settings & feedback, and the list of our other apps. Speech uses Apple's on-device
voices. The app asks for no permissions (no camera, microphone, contacts or location).
```

## 5. Age rating (App Store Connect's current questionnaire)

Result expected: **4+** (all answers below are in Apple's 4+ tier). "Made for Kids": **No** (not the Kids category).

| Section | Question | Answer | Why |
| --- | --- | --- | --- |
| In-App Controls | Parental Controls | No | The grown-up check is a gate, not a tool for parents to monitor or restrict content. |
| In-App Controls | Age Assurance | No | No age check or Declared Age Range API. |
| Capabilities | Unrestricted Web Access | No | No in-app browser; outside links open in Safari after the grown-up check; the in-app policy is a bundled page. |
| Capabilities | User-Generated Content | **No** (see note) | Apple's definition is *broad distribution* of user content. Names and one-word nickname words are shown only to the few people in one private, code-only room or family league; nothing is published, listed or kept public. |
| Capabilities | Social Media | No | No feed, discovery or sharing of user content beyond the room. |
| Capabilities | Messaging and Chat | **Yes** | Truthful answer: inside private rooms players can send six fixed preset phrases and type one-word nickname suggestions, which is direct communication. No free text, voice, images or links. In the 4+ tier. |
| Capabilities | Advertising | No | No ads. The "More Minik apps & games" card shows our own apps, unpaid, behind the grown-up check. |
| Mature Themes | Profanity or Crude Humor | None | Funny nicknames are mild words from a fixed list ("Banana", "Noodle"…); players type their own one-word suggestions in private rooms only. |
| Mature Themes | Horror/Fear Themes | None | |
| Mature Themes | Alcohol, Tobacco, or Drug Use or References | None | |
| Medical or Wellness | Medical or Treatment Information | None | |
| Medical or Wellness | Health or Wellness Topics | None | |
| Sexuality or Nudity | Mature or Suggestive Themes / Sexual Content or Nudity / Graphic Sexual Content and Nudity | None | |
| Violence | Cartoon or Fantasy Violence | None | A playground ball game (a soft foam or beach ball, a paint balloon that splashes colour); a hit only gives a penalty point; no injury, fighting or harm is shown. |
| Violence | Realistic Violence / Prolonged Graphic or Sadistic Realistic Violence | None | |
| Violence | Guns or Other Weapons | None | Balls only. |
| Chance-Based Activities | Gambling | No | |
| Chance-Based Activities | Simulated Gambling | None | |
| Chance-Based Activities | Contests | Infrequent | Matches have winners, a private family league has a standings table and the first new challenge each day earns bonus points; there are no prizes, public rankings or leaderboards. "Frequent" would make the app 13+, which does not describe it. |
| Chance-Based Activities | Loot Boxes | No | No random paid items. |

Note on User-Generated Content: answering "Yes" also stays 4+, but invites App Review to apply Guideline 1.2 (filtering,
reporting and blocking for user content). The app has no report or block button and no word filter beyond the
letters-only rule, so the review note above explains why the private, code-only rooms create no public content. If App
Review asks for 1.2 features, that needs an app change (decision for the owner).

## 6. App Privacy (the "nutrition label")

Privacy Policy URL: `https://miniklearn.com/apps/amodu/privacy-ios.html`. "Do you or your third-party partners collect
data from this app?" **Yes**. Tracking: **No** for every type (nothing is combined with other companies' data or used
for advertising; no ad SDK, no IDFA; `NSPrivacyTracking` is false).

| Data type | Collected | Linked to the user | Tracking | Purpose | Where it comes from |
| --- | --- | --- | --- | --- | --- |
| Identifiers > **User ID** | Yes | Yes | No | App Functionality | Firebase anonymous user ID for rooms, leagues and the lag diagnosis. |
| User Content > **Gameplay Content** | Yes | Yes | No | App Functionality | Room and league data: chosen game name and avatar, language flag, readiness/presence, rules and settings, moves, ball actions, penalties, preset-phrase events, typed one-word nickname suggestions and votes, results; league roster, rounds, wins, penalty points and earned nicknames (`Amudu/Online/OnlineRoom.swift`, `FamilyLeague.swift`). |
| Diagnostics > **Performance Data** | Yes | Yes | No | App Functionality | Only the optional 10-minute lag diagnosis: frame and connection timings, data sizes (`Amudu/Online/LagDiagnostics.swift`, stored under the anonymous ID). |
| Diagnostics > **Other Diagnostic Data** | Yes | Yes | No | App Functionality | Same diagnosis: app version and build, device model, interface language, host/guest role, error categories. |

Not collected (answer "not collected"): Contact Info, Health and Fitness, Financial Info, Location, Sensitive Info,
Contacts, Emails or Text Messages, Photos or Videos, Audio, Customer Support, Other User Content, Browsing and Search
History, Purchases (StoreKit checks ownership on the device; nothing about purchases reaches our servers), Usage Data,
Device ID, Crash Data, Other Data. The "More Minik apps & games" list is a plain download with no ID or game data.

Decisions for the owner:
- **Lag diagnosis.** It is opt-in and rare, but the data is not typed by the user with their name shown, so Apple's
  "optional disclosure" exemption does not fit; it is listed above. `Resources/Privacy/Amudu/PrivacyInfo.xcprivacy`
  declares the same four types (User ID, Gameplay Content, Performance Data, Other Diagnostic Data; linked, not
  tracking, App Functionality), so the manifest matches the label.
- **Send feedback** opens the user's own Mail app to appsbybros.dev@gmail.com. It fits Apple's optional-disclosure
  criteria (rare, optional, the user writes it and sends it from their own address), so it is not listed. To be
  stricter, add Contact Info > Email Address and User Content > Customer Support (App Functionality, linked).
- **Game names.** The name field asks for a game name and the policy recommends a nickname, so it is counted as Gameplay
  Content. If you expect many children to type their real first name, also add Contact Info > Name (App Functionality,
  linked).

## 7. Category, content rights, export compliance

- **Category:** Primary **Games**, game subcategories **Family** and **Sports**. Secondary category: none (or
  Entertainment). Do not choose the Kids category and do not tick "Made for Kids": the app has online rooms, a purchase
  that a grown-up check protects but that is not a parental gate in Apple's Kids sense, and a Firebase backend.
- **Content rights:** "Does your app contain, show, or access third-party content?" **No**, provided every character,
  picture, sound (`Amudu/Audio/`), font and text is Apps By Bros' own or licensed for this use (please confirm; the
  sound files' origin was not checked). The app shows only its own content and our own catalogue of Minik apps.
- **Export compliance:** `ITSAppUsesNonExemptEncryption` is `false` in the MinikAmudu Info.plist (`project.yml`), so
  App Store Connect does not ask per build. If asked: the app uses only encryption built into iOS and Firebase's HTTPS
  (exempt); answer "None of the algorithms mentioned above" / no proprietary or non-standard encryption; no
  documentation upload is needed.
- **Pricing:** the app is Free; only the in-app purchase has a price (owner's choice).
- **Copyright:** `appstore/metadata/copyright.txt` ("2026 Apps by Bros").

## 8. Facts this is based on

- Bundle and purchase: `project.yml` target `MinikAmudu` (`PRODUCT_BUNDLE_IDENTIFIER com.appsbybros.minik.spud`,
  `SPUD_FULL_GAME_PRODUCT_IDENTIFIER com.appsbybros.minik.spud.full_game`, `CFBundleLocalizations` en, he, ar, es, hi,
  nl, `ITSAppUsesNonExemptEncryption: false`).
- Firebase products linked to MinikAmudu: **FirebaseCore, FirebaseAuth, FirebaseDatabase only** (no Analytics,
  Crashlytics, Messaging, Firestore or App Check). No Google Mobile Ads; `Tests/AmuduTests/SpudAccessTests.swift`
  fails if any file under `Amudu/` mentions it.
- Free tier and gate: `Amudu/Store/SpudAccess.swift`, `SpudAccessModel.swift`, `SpudUnlockScreen.swift` (purchase
  behind `model.parentGate`); `AppModel.openSettings` and `openPolicyLink` are gated; the gate is a multiplication
  (`AppModel.parentGate`).
- Online: `minikAmudu/rooms`, `leagues`, `leagueCodes`, `leagueUsers`, `leagueInvites`, `diagnostics`
  (`Amudu/Online/`); preset phrases `Words.phrasesEn` (six); nickname words `Words.validSuggestion` (1-24 letters/digits);
  names `Words.validName` and the database rules (`C:\Projects\MinikAmudu\firebase\database.rules.json`).
- Speech: `AVSpeechSynthesizer` in `Amudu/Game/GameAudio.swift`; no permission keys in the Info.plist.
- The "More Minik apps & games" card downloads `familyApps/catalog.json` from the same database at most daily, with no
  sign-in or ID (`Family/FamilyCatalog.swift`); Spud never shows the family promotion breaks or remove-ads reminders.
