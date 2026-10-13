# Minik family messages on iPhone

Port of the shared Android module `C:\Projects\MinikFamilyServices` (FamilyCatalog, FamilyMessagePolicy,
FamilyMessages, FamilyText, FamilyAdultGate) to `Family/`, used by every iPhone app whose Android twin
hosts it.

## What it does

- **More Minik apps & games**: a card for another Minik app chosen from the public catalogue (weighted,
  never the app itself): artwork, title, description, "Discover all our apps and games at
  miniklearn.com." and link buttons ("Meet this app", "Play on the website", "Also available for
  iPhone", "All our apps & games"); "Keep playing" closes it. Every link opens behind a grown-up gate.
  With no catalogue entry it opens the apps directory instead.
- **Ad-break promotion**: at one eligible ad break in 30 (at most once a day) the card replaces the
  interstitial, and the app's ad cadence counts it as shown. As on Android, only a break that has a
  loaded interstitial counts, never before the store has answered whether Remove Ads is owned, and no
  ad opens while a family message is up.
- **Remove-ads reminder**: "Ad-free play" with Remove ads / Remind me later / Don't show again, due
  14 days after the first launch, then at most every 14 days; "Don't show again" is permanent.
- The catalogue is refreshed at most once a day from
  `https://minikswish-default-rtdb.europe-west1.firebasedatabase.app/familyApps/catalog.json` (public
  read; no account, device or gameplay identifiers are sent). The last valid copy is kept; the
  bundled `minik-family-catalog.json` (Android's asset copy) is the fallback.

## Where each app shows it

| App | Android host | iPhone |
| --- | --- | --- |
| Minik Plus, Minik Plus English | DailyLearningActivity (from the Parent Area); InterstitialHelper promotion | Parent Area footer "Menu" → "More Minik apps & games"; promotion in `MinikAdCoordinator` |
| Minik Math Plus | ParentScreens button (after Speech, before Feedback) | Parent Area button before the support and feedback links |
| Minik Ping Pong | PlayActivity Advanced link; AdCoordinator promotion and idle-menu reminder | Link above "Parents / adults"; promotion in `MPAds.completed`; reminder 1.5 s after the home appears |
| Multi Ping Pong | PlayActivity Advanced link (ads off) | Link at the end of the home |
| Spud, Splash, Minik Squash, Minik Beach Volley | Home "Advanced" link (FamilyMenu.organize), the app's own parent gate | Same, with the app's own gate; no ads, so no promotion or reminder |
| Minik Math (web app), Minik Retro Ping Pong | none | none |

`FamilyOverlay()` sits above each app's root view (the Minik apps: `RootView`; a second copy above the
Minik Parent Area sheet shows cards opened there). Only the overlay that appeared last draws the card,
gate and reminder, so a card is never drawn twice. In Spud, Splash and the sports apps the overlay sits
under the app's own grown-up gate and toasts, which the card's links open. Each app names its catalogue key in Info.plist
(`MinikFamilyCatalogKey`: minik, math-plus, pong, multiplayer, spud, splash, squash, volley) so it never
promotes itself.

## Differences from Android

- No "View on Google Play" button on iOS.
- The app is recognised by its catalogue key instead of Android package names and aliases.
- The cadence is stored as JSON in UserDefaults (`minik_family_messages.cadence`) instead of Java
  Properties.
- The bundled artwork is high-quality JPEG (5.5 MB instead of Android's 21 MB of PNG) in
  `Family/FamilyArt.xcassets` as `family-<name>`; only the apps that show the card bundle it.
- Languages, as on Android: Minik Plus and Math Plus use their in-app interface language; Minik Ping
  Pong is English, or Hebrew on a Hebrew device; Multi Ping Pong, Spud, Splash and the sports apps use
  their app language.
- The grown-up gate accepts any Unicode decimal digits, like Java's `Integer.parseInt`, and asks for
  an ASCII number pad.
- Android Squash/Volley label the menu entry with the sports `tr()` text, which has no translation in
  Spanish, Arabic, Hindi or Dutch, so `FamilyMenu.organize` there leaves an untranslated button above
  the sections in those languages; iOS uses the family text and puts the link in Advanced.

## Regenerating

- Texts: `FamilyText.swift` is generated from `FamilyText.java` (20 rows, 10 languages besides English
  and Hebrew).
- Catalogue and art: copy `android/src/main/assets/minik-family/catalog.json` to
  `Family/minik-family-catalog.json`; convert each `art/*.png` to `family-<name>.jpg` (quality 90).
