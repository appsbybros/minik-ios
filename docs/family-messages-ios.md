# Minik family messages on iPhone

Port of the shared Android module `C:\Projects\MinikFamilyServices` (FamilyCatalog, FamilyMessagePolicy,
FamilyMessages, FamilyText, FamilyAdultGate) to `Family/`, used by every iPhone app whose Android twin
hosts it, plus `FamilyKit` (below), the shared SwiftUI look of the Android family UI classes.

## 2026-10-24 sync

iOS matches MinikFamilyServices `31e380d` (from `dcfdd13`: `82e8721`, `514b7cf`, `69ba3d0`, `2e1f428`,
`8323ba0`, `2f75e98`, `6a27708`, `31e380d`). The catalogue, art, texts and message policy did not change.

- Raised-button lettering (`FamilyButtonAlignment`, new): `FamilyKit.RaisedLettering` measures the ink
  of the label's own shaped text (`Text.LayoutKey`, drawn into a mask as Android rasterises its
  `Layout`) and moves the letters, by a translation, to the centre of the raised face below the upper
  gloss (`SkyLook.textFaceRect`, Android `copyTextFaceBounds`) plus 3 points; the face follows the
  press. `FamilyKit.Lettering.fullRaisedFace = true` is Android `useFullRaisedFace(true)` (the whole
  face, `SkyLook.faceRect` / `copyFaceBounds`). `SkyButtonStyle` (not on panels) and `MenuButtonStyle`
  apply it, as Android binds `FamilySkyUi.button`, `FamilyMenu.style`, sky dialog buttons, the
  tournament exit buttons and every Button on a `FamilySkyDrawable`.
- Family card: no dialog button any more; "Keep playing" is a full-width flat mint (`#C8F1E6`)
  52-point button at the end of the card's box, 16 points below the links. Link buttons are 12 points
  apart, have no side padding and their text sits 1.5 points above centre; 10 points below the eyebrow
  and 12 below the art; the box has 16 points of padding at the top and 20 at the bottom.
- Not ported: `FamilyButtonAlignmentDeviceTest`, the QA reports and the QA skill (Android device QA).
  The apps' own sky copies (`Amudu/UI/SkySurface.swift`, `Splash/App/SplashSky.swift`,
  `Sports/App/SportsSky.swift`) are app code, not `Family/`; they can apply `FamilyKit.RaisedLettering`
  to their labels.

## 2026-10-13 sync

iOS matches MinikFamilyServices `dcfdd13` (the code is `ee0505d`; `dcfdd13` adds only docs and the QA
skill). The catalogue (`android/src/main/assets/minik-family/catalog.json`), the 27 art files, the
message policy and its test were already as ported on the morning of 13 October.

- Texts: three new `FamilyText` rows ("For a wider view, play in landscape.", "More options below. Tap
  to scroll", "More below") in all ten extra languages.
- Family dialogs: Android now styles every family dialog with `FamilySkyUi.dialog` (via
  `FamilyDialogStyle.apply`), so the card, the grown-up gate and the remove-ads reminder are light sky
  panels with 24-point corners and raised buttons (positive/neutral blue `#A6DCFF`, negative pink
  `#FFD4E6`); the gate's answer field has the `FamilyFormStyle` look (white, 8-point corners, grey
  border, blue while focused). The reminder is now this dialog instead of the system alert.
- `FamilyKit` ports the new shared Android UI classes for the apps to call (see "Shared UI").
- `Scripts/audit-family.py` compares texts, Hebrew pairs, catalogue and art with Android.
- Not ported: the public `catalogue/catalog.json` (the deployed copy, with a disabled `minik-maze`
  entry; apps bundle the asset copy, as on Android), `FamilyMenu.organize` (Android re-parents existing
  buttons; the iOS apps build their sections directly), `FamilyFormStyle.watch` and `FamilySkyUi.watch`
  (Android restyles views it finds; iOS apps apply `FormField`/`SkySurface` where they draw them),
  `SharedFamilyHostDeviceTest` and the QA skill (Android device QA).

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
| Minik Plus, Minik Plus English | DailyLearningActivity (from the Parent Area); InterstitialHelper promotion | Link at the end of the Parent Area card; promotion in `MinikAdCoordinator` |
| Minik Math Plus | ParentScreens button (after Speech, before Feedback) | Link in the Parent Area before the support and feedback links |
| Minik Ping Pong | PlayActivity Advanced link; AdCoordinator promotion and idle-menu reminder | Link above "Parents / adults"; promotion in `MPAds.completed`; reminder 1.5 s after the home appears |
| Multi Ping Pong | PlayActivity Advanced link (ads off) | Link at the end of the home |
| Spud, Splash, Minik Squash, Minik Beach Volley | Home "Advanced" link (FamilyMenu.organize), the app's own parent gate | Same, with the app's own gate; no ads, so no promotion or reminder |
| Triple Shot | "More Minik apps & games" button on the skill journey's settings page (BasketballJourneyActivity) behind FamilyAdultGate; the Home sections and info link use FamilyMenu | Same page, button and gate through `FamilyBridge.showMoreApps` (`TripleShot/Family/FamilyBridge.swift`); no ads, so no promotion or reminder |
| Minik Retro Ping Pong (Bounce & Learn) | AdCoordinator promotion and idle-menu reminder; "More Minik apps & games" in the parents page (MonetizationActivity) | Link in the parents page; promotion through `MinikFamilyAdBreak`; idle-menu reminder |
| Minik Math (web app) | none | none |

`FamilyOverlay()` sits above each app's root view (the Minik apps: `RootView`; a second copy above the
Minik Parent Area sheet shows cards opened there). Only the overlay that appeared last draws the card,
gate and reminder, so a card is never drawn twice. In Spud, Splash and the sports apps the overlay sits
under the app's own grown-up gate and toasts, which the card's links open. Triple Shot, whose screens are the
translated Android views, shows its one `FamilyOverlay` in a hosting controller above its activities and dialogs
and below its toasts. Each app names its catalogue key in Info.plist
(`MinikFamilyCatalogKey`: minik, math-plus, pong, multiplayer, spud, splash, squash, volley, bounce, tripleshot) so it never
promotes itself.

## Differences from Android

- "More Minik apps & games" is always a quiet underlined link (Android `FamilyMenu.link`, `FamilyMenuLink`
  on iOS), never a regular app button, also in Minik Plus and Math Plus, where Android uses buttons.
  Triple Shot, a line-by-line port of its Android views, keeps Android's button.
- No "View on Google Play" button on iOS.
- The app is recognised by its catalogue key instead of Android package names and aliases.
- The cadence is stored as JSON in UserDefaults (`minik_family_messages.cadence`) instead of Java
  Properties.
- The bundled artwork is high-quality JPEG (5.5 MB instead of Android's 21 MB of PNG) in
  `Family/FamilyArt.xcassets` as `family-<name>`; only the apps that show the card bundle it.
- Languages, as on Android: Minik Plus and Math Plus use their in-app interface language; Minik Ping
  Pong is English, or Hebrew on a Hebrew device; Multi Ping Pong, Spud, Splash and the sports apps use
  their app language; Triple Shot never sets one, so its family texts follow the device language.
- The grown-up gate accepts any Unicode decimal digits, like Java's `Integer.parseInt`, and asks for
  an ASCII number pad.
- The card's lilac content box has rounded corners inside the 24-point sky panel (Android's
  rectangular content view leaves square corners over the rounded window).
- The "More below" arrow is the SF Symbol `chevron.down` (Android draws the "⌄" character).
- Android Squash/Volley label the menu entry with the sports `tr()` text, which has no translation in
  Spanish, Arabic, Hindi or Dutch, so `FamilyMenu.organize` there leaves an untranslated button above
  the sections in those languages; iOS uses the family text and puts the link in Advanced.

## Shared UI (`FamilyKit`)

`Family/FamilyKit.swift`, `FamilyKitMenu.swift` and `FamilyKitPages.swift` port the Android classes the
apps share. Everything is nested in `enum FamilyKit` so no app type clashes with it. Colours are
Android ARGB `UInt32` values. The apps call them where their Android twin uses the class:

| Android | iOS | Android callers |
| --- | --- | --- |
| `FamilySkyDrawable` | `FamilyKit.SkySurface(color:cornerRadius:panel:pressed:strokeWidth:strokeColor:faceColors:)` as a background; `FamilyKit.Sky.palette`, `.blend`, `.isPanelColor` | Squash/Volley, Splash and Spud `bg()` (panel for white, `#F5F7FD`, `#F6F8FF`); Spud PictureChoices; Pong and Multi Pong `surface()`, SettingSelector, TeamLobbyCards, KnockoutBracketView |
| `FamilySkyUi.button` | `.buttonStyle(FamilyKit.SkyButtonStyle(color:cornerRadius:panel:))` | buttons on sky faces |
| `FamilyButtonAlignment` | built into `SkyButtonStyle` and `MenuButtonStyle`; `.modifier(FamilyKit.RaisedLettering(cornerRadius:pressed:))` on a label before its `SkySurface` background; `FamilyKit.Lettering.fullRaisedFace` | every Button on a `FamilySkyDrawable`; Spinner labels (`bind(text, surface)`); `useFullRaisedFace` per app |
| `FamilySkyUi.dialog` | `FamilyKit.SkyDialog { ... }` with `FamilyKit.SkyDialogButton(_:role:textColor:uppercase:action:)` | Splash and Spud `GameDialogBuilder`; the family dialogs (done) |
| `FamilyMenu.section`, `.style`, colours | `FamilyKit.MenuSection(_:color:open:toggle:content:)`, `.buttonStyle(FamilyKit.MenuButtonStyle(color:))`, `FamilyKit.MenuColor` | Squash/Volley, Splash, Spud (`organize`); Pong and Multi Pong `menuSection` (Pong then repaints the panel dark with white headings) |
| `FamilyMenu.link` | `FamilyMenuLink(title:action:)` (unchanged) | every app |
| `FamilyMoreFrame` | `FamilyKit.MoreBelowScroll(light:language:content:)` in place of the menu's `ScrollView` | every `FamilyMenu.section` host (light only in Squash/Volley); Pong and Multi Pong `MenuMoreFrame` |
| `FamilyReadingPanel` | `FamilyKit.ReadingColumn(landscape:) { ... }` inside the page scroll view; `FamilyKit.readingWidth(_:landscape:)` | Squash/Volley, Splash, Spud pages; Pong and Multi Pong `ReadingPanel` (with their own maximum) |
| `FamilyTournamentUi.divider` | `FamilyKit.TournamentDivider()` | Squash/Volley and Splash online pages; Pong and Multi Pong PlayActivity (twice) and the online-teams page |
| `FamilyTournamentUi.confirmSave` | `FamilyKit.TournamentExitDialog(title:message:save:discard:cancel:onSave:onDiscard:onCancel:)` | Squash/Volley and Splash `leaveCupScreen`; Pong and Multi Pong `confirmTournamentExit` |
| `FamilyLandscapeHint.show` | `.modifier(FamilyKit.LandscapeHint(language:))` on the game view | Squash/Volley, Splash, Spud games; Pong (Modern, Journey, OnlineTeams, PrivateMatch); Multi Pong (Cross, CrossJourney, CrossOnlineTeams, PrivateMatch) |
| `FamilyFormStyle` | `.modifier(FamilyKit.FormField(focused:minHeight:))`, `FamilyKit.FormColor.hint` for prompts | every host's text fields (Android applies it to each activity that uses `FamilyMessages` or `FamilyMenu`); Minik Plus daily learning and Math Plus parent fields |

## Regenerating

- Texts: `FamilyText.swift` is generated from `FamilyText.java` (23 rows, 10 languages besides English
  and Hebrew). `python Scripts/audit-family.py` checks texts, catalogue and art against Android.
- Catalogue and art: copy `android/src/main/assets/minik-family/catalog.json` to
  `Family/minik-family-catalog.json`; convert each `art/*.png` to `family-<name>.jpg` (quality 90).
