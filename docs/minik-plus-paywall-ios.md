# Minik Plus and Minik Plus English: no ads, a free week, then a one-time purchase (iOS 1.8.0)

Owner decision of 12 November 2026, shared with Android. Only the `MinikPlus` (com.appsbybros.minik.plus) and
`MinikPlusEnglish` (com.appsbybros.minik.plus.english) targets change. Every other app (Math, Math Plus, the Ping
Pong apps, Amudu, Splash, Sports, Triple Shot) keeps its ads, its Remove Ads purchase and its version.

Nothing here has been compiled yet: the first compile is the CI Compile Check.

## What changed

**No ads, and no ad SDK in the two binaries.**

- `project.yml`: the two targets no longer depend on the GoogleMobileAds package and carry no AdMob IDs.
  `GADApplicationIdentifier`, the Remove Ads product and the other ad Info.plist keys moved from the shared
  `MinikApplication` template into a new `MinikAdSupportedApplication` template. The five apps with ads list it
  (`templates: [MinikApplication, MinikAdSupportedApplication]`), so their Info.plists are unchanged. The two Plus
  targets do not.
- Both targets compile with `MINIK_NO_ADS`. Every `#if canImport(GoogleMobileAds)` in the shared code
  (`Sources/GoogleMobileAdsInterstitialService.swift`, `Sources/ModernPong/MPAds.swift`) also needs
  `!MINIK_NO_ADS`. Without it, a GoogleMobileAds module that another app left in a shared DerivedData (the CI
  Compile Check shares one) could be compiled and auto-linked into Minik Plus.
- The ad coordinator never starts and the Remove Ads reminder is never evaluated when the paywall is configured.
  The Remove Ads button on the intro and in the Parent Area is gone.
- There was never an ATT prompt, `NSUserTrackingUsageDescription`, `SKAdNetworkItems` or UMP consent code in the
  repository, so nothing needed removing there. The privacy manifest (`Resources/Privacy/Language`) declares no ad
  data.
- `appstore/privacy/Minik*/…/privacy.html`: the "Ads and children" section became "No ads", and "Purchases"
  became "Free week and purchase". AdMob left the providers paragraph and the links. The store descriptions never
  mentioned ads.

**Free week and buy wall.**

- Products come from Info.plist keys set per target in `project.yml`:

  | Target | `MinikFullAccessProductIdentifier` | `MinikFreeWeekProductIdentifier` | `MinikLegacyRemoveAdsProductIdentifier` |
  |---|---|---|---|
  | MinikPlus | `minik_plus_full_access` | `minik_plus_free_week` | `remove_ads_minik` |
  | MinikPlusEnglish | `minik_english_full_access` | `minik_english_free_week` | `remove_ads_minik_english` |

  The other apps have none of these keys (`MinikCommerceConfiguration.paywall == nil`), so they keep their exact
  one-product catalog.
- `Sources/MinikPlusAccess.swift` holds the decision as a small pure type, `MinikPlusAccessPolicy.access(…)`:
  - **Owned full access, or the earlier Remove Ads product, gives `.fullAccess` forever.** The legacy product is
    mapped to the same entitlement in the StoreKit catalog. The Remove Ads flag an earlier version cached on the
    device also counts at once, even offline.
  - **The free week started → `.trial(daysLeft:)`.** It ends at start + 7 × 24 h. Days left = ceil(remaining / 24 h),
    shown as 1 to 7.
  - **Nothing started → `.trialNotStarted`** (the welcome screen).
  - **The week is over → `.trialEnded`** (the wall).
  - **The clock going backwards never adds time.** The week counts from the later of now and the latest time this
    device has seen. A clock set before the start leaves the week whole, never longer.
- The week's start is the App Store's own date: `StoreKitFreeWeekStartReader` reads the earliest verified
  `Transaction.all` entry for the free-week product, using the earlier of `purchaseDate` and
  `originalPurchaseDate`. So it survives reinstalls and is the same on every device of the Apple Account. The
  device keeps it (and full access) in `MinikPlusAccessRepository` for offline launches. The start only ever moves
  earlier. If the date cannot be read right after the free product is taken, the week counts from that moment.
- Access codes ("I have a code") are not offered: the iOS apps never supported them, so they are neither on the wall
  nor part of the grandfathering.
- **Screens** (`Sources/MinikPlusPaywallView.swift`):
  - **The welcome and the wall are one view.** RootView shows it full-screen over everything; an opaque layer takes
    every touch and the hub is hidden from VoiceOver.
    - Before the free week: "Try Minik Plus free for 7 days". It says the week lasts 7 days, that after it the whole
      app is locked, and the one-time price. Buttons: Start free week, Unlock everything – {price}, Restore Purchases.
    - After the week: "Your free week is over". Buttons: Unlock everything – {price}, Restore Purchases.
    - Both have small Privacy Policy and Support links.
  - **The grown-up check (the existing `ParentalGateView`) comes before every one of these buttons and links.**
  - **Without a price,** the button reads "Unlock everything" with a spinner. If the store is unreachable it shows
    "Can't reach the store right now…" with Try again, and also retries every 15 s while the wall is up.
  - **After a purchase or restore,** a "Thank you! Everything is unlocked." note shows and the wall closes; the app
    stays where it was.
  - **During the week:**
    - The intro shows a small "N days left in your free week" chip where Remove Ads was. A tap opens the grown-up
      check, then the same screen with a close button.
    - The Parent Area's Purchases page shows the same line, a gated Unlock everything button and Restore Purchases.
- **The lock is checked:**
  - at launch
  - when the app becomes active again
  - before Practice opens the menu
  - before any activity starts
  - on the way back to the menu. An activity already running is allowed to finish.
- App Store screenshot and parity captures (`-MinikScreenshotScene`) never show the wall.
- Every new text is translated into the languages the two targets ship. Minik Plus has 11: en, am, ar, de, es, fr,
  he, nl, pt-BR, pt-PT, ru. Minik Plus English has the same without he. The day count uses plural variations in
  both String Catalogs.
- Version: `MINIK_MARKETING_VERSION` is "1.8.0" for these two targets only. The shared value stays 1.7.9, and build
  numbers are unchanged.

## Parent Area: one grown-up check per visit (15 November 2026)

As promised in the App Review reply for Minik Plus, the grown-up check (`ParentalGateView`) comes before the Parent
Area opens. This applies in every app that shows `ParentAreaView`: Minik Plus, Minik Plus English and Minik Math Plus,
all through `MinikActivityHubView`.

- One passed check covers the whole visit. Purchases, Restore, the outside links, the leaderboard switches, and
  rate/share/feedback inside the Parent Area no longer ask again.
- Its own pages (Progress, Records, Learning progress) return into the same visit (`ParentAreaVisit`). Leaving the
  Parent Area ends the visit, and the next visit asks again.
- Purchases reachable from outside the Parent Area keep their own check:
  - the welcome screen, the wall and the free-week chip;
  - the Remove Ads reminder;
  - Minik Math's parents page, Minik Bounce's parents sheet, and Minik Ping Pong's purchase sheet.
- `Scripts/audit-parent-release-source.ps1` checks all of this.

## App Store Connect setup (owner)

For each app, create two In-App Purchases (Monetization > In-App Purchases):

| App | Product ID | Type | Price | Display name |
|---|---|---|---|---|
| Minik Plus | `minik_plus_full_access` | Non-Consumable | the chosen one-time price | e.g. "Full access" / "גישה מלאה" |
| Minik Plus | `minik_plus_free_week` | Non-Consumable | **Free** (price tier 0) | **"7-day Trial"** (Guideline 3.1.1) |
| Minik Plus English | `minik_english_full_access` | Non-Consumable | the chosen one-time price | e.g. "Full access" |
| Minik Plus English | `minik_english_free_week` | Non-Consumable | **Free** (price tier 0) | **"7-day Trial"** |

1. Give each product a localized display name and description. In the description of the free one, say that the
   app is locked after the 7 days until full access is bought. Each product also needs a review screenshot (the
   welcome screen).
2. Leave Family Sharing off on the two free-week products.
3. Attach all four products to version **1.8.0** of their app ("In-App Purchases and Subscriptions" on the version
   page). First-time IAPs can only be reviewed together with an app version.
4. **Remove the old Remove Ads IAP (`remove_ads_minik`, `remove_ads_minik_english`) from the pending submission.**
   Do not delete it: owners keep full access through it, and Restore still finds it if you later take it off sale.
5. App Privacy: remove the data types declared for Google AdMob (third-party advertising, device and usage data
   collected by the ad SDK). The leaderboard's User ID and Gameplay Content for App Functionality stay.
6. Review notes: "No ads. A grown-up check (an addition problem) protects every purchase. On first launch, Start free
   week takes the free '7-day Trial' product; after 7 days the app is locked until 'Unlock everything' is bought.
   Restore Purchases recovers both."
7. The AdMob apps for Minik Plus and Minik Plus English are no longer used by iOS 1.8.0.

The repository has no app-level StoreKit configuration file (only the commerce package's test fixture), so Xcode
runs use the sandbox. A local `.storekit` file with the four products above can be added to the MinikPlus scheme if
wanted.

## What to test in TestFlight (sandbox)

Use a sandbox Apple Account. To start again, delete the app and clear the account's purchase history (Settings >
App Store > Sandbox Account > Manage).

1. **Fresh install:** the welcome screen covers the app; nothing behind it can be tapped.
   - It shows the price in "Unlock everything – {price}" and the terms text with the price.
   - Each button and each link asks the grown-up question first; Cancel returns to the welcome screen.
2. **Start free week:** the App Store sheet shows the free "7-day Trial".
   - Afterwards the welcome screen closes, the intro shows "7 days left in your free week", and the Parent Area >
     Menu > Purchases page shows the same line with Unlock everything.
3. **Chip:** tap it, pass the grown-up check, and the buy screen opens with a close button; close it.
4. **End of the week:** set the device date 8 days ahead (Settings > General > Date & Time).
   - Return to the app: the wall "Your free week is over" appears, and no activity opens.
   - Setting the date back does not reopen the app (by design).
5. **Buy:** Unlock everything → purchase → "Thank you! Everything is unlocked." The wall closes and stays closed after
   relaunch, offline too (airplane mode).
6. **Reinstall / second device, same sandbox account:**
   - The free week keeps its first date (no new week).
   - A bought full access returns at launch or with Restore Purchases.
7. **Grandfathering:** a sandbox account that bought `remove_ads_minik` (or `remove_ads_minik_english`) with the
   earlier version never sees the welcome or the wall after updating.
8. **Offline at first launch:** the wall shows "Can't reach the store right now…" and Try again. Back online, the
   price appears by itself within about 15 s.
9. **No ads anywhere:** no interstitial after activities, no Remove Ads button or reminder, no tracking prompt.
10. **Languages:** switch the interface language in the Parent Area (Hebrew, Arabic, Russian…). The welcome, the
    wall, the chip and the Parent Area texts follow it, and Hebrew and Arabic are right-to-left.
11. **Parent Area:** the grown-up question comes before it opens. Inside, Restore, Unlock, the links and the
    leaderboard switch work without a second question. Closing the Parent Area and opening it again asks again.
12. **The other apps are unchanged:** Minik Math Plus, Minik Math and Minik Ping Pong still show their ads and Remove
    Ads, and keep version 1.7.9.
