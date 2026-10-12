# Apple release checklist

Status: handoff for the four existing Apple products plus the new standalone Retro Pong target (Apple registration/signing pending). The Modern Ping Pong Firebase Apple registration below was created on 2026-09-28; Apple Developer/App Store Connect and production AdMob setup remain pending.

## READY IN REPO

| Product | Bundle ID | Display name | Suggested owner SKU | Source version/build | Firebase | Ads/Remove Ads source exposure |
| --- | --- | --- | --- | --- | --- | --- |
| MinikPlus | `com.appsbybros.minik.plus` | Minik Plus | `MINIKPLUS-IOS` | `1.7.9` / `79` | Target-specific production plist; anonymous Auth/Firestore/App Check source | Language ad opportunities; Parent purchase/restore |
| MinikPlusEnglish | `com.appsbybros.minik.plus.english` | Minik Plus English | `MINIKPLUSENGLISH-IOS` | `1.7.9` / `79` | Target-specific production plist; anonymous Auth/Firestore/App Check source | Language ad opportunities; Parent purchase/restore |
| MinikMathPlus | `com.appsbybros.minik.math.plus` | Minik Math Plus | New record; owner to choose (for example `MINIKMATHPLUS-IOS`) | `1.7.9` / `79` | None | Parent purchase/restore (`remove_ads_math_plus`, a new App Store product); new Retro route has no ad opportunity |
| MinikMath | `com.appsbybros.minik.math` | Minik Math | `MINIKMATH-IOS` (the existing record) | `1.7.9` / `79` | None | Android Minik Math's web app: interstitial after finished rounds on Android's schedule; "Parents · Remove ads" → grown-up gate → `remove_ads_math` purchase/restore |
| MinikPingPong | `com.appsbybros.minik.pingpong` | Minik Ping Pong | `MINIKPINGPONG-IOS` | `1.7.9` / `79` | Apple registration in `minikswish`; Auth/RTDB under `minikPingPong/` | Debug test ads; Release disabled; StoreKit purchase/restore/code UI |
| MinikRetroPingPong | `com.appsbybros.minik.bouncelearn` | Minik Bounce | Owner to choose | `1.7.9` / `79` | None | Like Android Bounce: interstitial after a finished game (AdMob app `~9515819906`), "For parents" → grown-up gate → `remove_ads` purchase/restore |

All shipping identifiers route through explicit XcodeGen settings. The reusable unit-test bundle is `com.appsbybros.minik.tests`. Source rejects old `com.minik.minik.plus*` and `com.example.temporary.*` shipping identifiers. The shared version strategy is one repository release version/build (`MINIK_MARKETING_VERSION` / `MINIK_BUILD_NUMBER`) applied to all targets; increment the build for every App Store upload and set a product-specific marketing version only if App Store history requires divergence. Do not invent an Apple numeric app ID or Team ID in source.

Only MinikPlus and MinikPlusEnglish require the App Attest capability/entitlement currently present in source. Local notifications require user authorization but no remote-push capability. StoreKit and Google Mobile Ads add no app-owned entitlement here. Math remains without Firebase. Modern Ping Pong links Auth/RTDB using its own registration; it has no App Attest entitlement. Language App Check configuration is unchanged.

Signing insertion points are explicit: `project.yml` currently sets `settings.base.CODE_SIGN_STYLE: Automatic`. After the Team ID exists, select the team in the generated Xcode project or inject `DEVELOPMENT_TEAM` through the owner's protected release configuration/command line. If the owner chooses manual signing, override `CODE_SIGN_STYLE`, `CODE_SIGN_IDENTITY`, and `PROVISIONING_PROFILE_SPECIFIER` in protected release configuration. Do not commit certificates, private keys, provisioning profiles, account credentials, or an invented Team ID.

Privacy, support and terms defaults are `https://miniklearn.com/privacy`, `https://miniklearn.com/contact`, and `https://www.easycallandanswer.com/terms.html`. The live privacy page must be replaced/approved as described in `docs/privacy-policy-website-replacement.md` before a leaderboard-enabled release.

## OWNER ACTION — Apple Developer and App Store Connect

For each product being distributed (including Retro if published):

1. Register the explicit Bundle ID above in Certificates, Identifiers & Profiles under the correct legal account/team. Record the real Team ID outside source secrets.
2. Create or reconcile the App Store Connect app record with the exact bundle ID, SKU chosen by the owner, primary language, display name, and platform. Record Apple's generated numeric app ID; do not backfill a guessed value.
3. Choose the signing team and distribution method; create/reconcile development, App Store distribution and any required device profiles/certificates.
4. Reconcile App Store version history. Use source `1.7.9` / `79` only if available; otherwise set the next valid marketing version/build and update the checked-in strategy before archiving.
5. Choose primary/secondary category. For MinikPlus, MinikPlusEnglish, MinikMathPlus and MinikMath, review Education; for MinikPingPong, review Games and its subcategories. These are owner choices, not checked-in facts.
6. Complete Apple's current age-rating questionnaire accurately, including public leaderboard, parental controls, advertising state, and game content. Separately decide whether each product is “Made for Kids” and choose its age band. Do not mark it casually: after approval, Apple restricts changing that selection and future releases must continue to meet Kids requirements.
7. Enter and publish the final Privacy Policy URL, Support URL, and terms/EULA choice. Use Apple's standard EULA unless legal approves the existing terms URL as a custom EULA where appropriate.
8. Complete App Privacy answers from `docs/app-store-privacy-data-inventory.md`, including submitted-binary Firebase, StoreKit, and any enabled Google Mobile Ads behavior. Review each archive's aggregate privacy report first.
9. Complete export-compliance questions from the actual binary. Current app source adds no custom encryption, but Firebase/HTTPS/StoreKit/ads SDK transport and Apple's current exemption questions must be reviewed; do not assert an exemption without the account owner.
10. Prepare localized app name/subtitle/description/keywords/promotional text, copyright/legal seller details, contact information, and review notes. Review notes must explain the grown-up gate, how to reach Parent Area, the optional curated-alias leaderboard and deletion control, restore purchase, local reminders, and whether ads are disabled or how reviewers can observe them.
11. Supply required iPhone and iPad screenshots from the validated release build, with no Android UI. Add previews only if the owner chooses them. Screenshot sizes/locales cannot be finalized without runtime capture.
12. Confirm agreements, tax and banking status before configuring paid products.

For each of the four apps, create one non-consumable IAP with exact Product ID `remove_ads`, localized display name/description, price, review screenshot and review notes; attach it to the appropriate submission and test purchase, pending/cancel, restore and Family Sharing choices. Each app owns its own App Store Connect product even though the source product ID string is shared.

Modern Ping Pong now exposes the requested StoreKit purchase, restore and Apple offer-code redemption. Configure its own `remove_ads` product, localized price/metadata and offer codes in App Store Connect. Purchases and codes still require Sandbox/TestFlight verification; the Android code backend is not used for Apple purchases.

## OWNER ACTION — Firebase and AdMob

- In Firebase project `easycallandanswer`, confirm both canonical Apple Language app registrations/plists and API-key/service restrictions. Enable **Authentication → Sign-in method → Anonymous**.
- The exact Auth console path is:

  ```text
  Firebase Console
  Authentication
  Sign-in method
  Anonymous
  Enable
  ```

- Execute the selected archive/clear ownership cutover in `docs/firebase-leaderboard-migration.md`: first complete and emulator-test the updated Android client, verify an administrator export, clear only the active legacy leaderboard collections during maintenance, then deploy the checked-in indexes and strict Rules. Do not let any client claim a legacy UUID.
- Register App Check/App Attest for both Apple Language apps. Keep enforcement off, distribute legitimate clients, and monitor Android and Apple validity metrics before any enforcement decision.
- Decide per product whether Google Mobile Ads is legally/policy approved. For every enabled product, create the iOS AdMob app using its exact Apple bundle ID and provide its production **AdMob application ID** and **interstitial ad-unit ID** through `MINIK_ADS_APPLICATION_IDENTIFIER` and `MINIK_INTERSTITIAL_AD_UNIT_IDENTIFIER`; then set both enable/policy flags to `YES`. Never use Google sample/test IDs in Release.
- MinikPlus and MinikPlusEnglish have Language placements. MinikMathPlus remains unchanged; MinikMath follows Android Minik Math's ad schedule. Modern Ping Pong has its own completed-match adapter: Google test ads in Debug only and Release disabled. Production iOS IDs and approved release configuration must be added before enabling it; the old Language adapter flags do not activate Modern production ads.
- Modern Ping Pong Apple app `1:12298786440:ios:bfc268456a87978e75f13d` is registered to `com.appsbybros.minik.pingpong` in `minikswish`. Its plist is checked in. Anonymous Auth and RTDB rules were already enabled/published by the owner; no rules or TripleShot data were changed in this port. Verify the iOS API key restrictions and a real signed iOS client before release.

## LEGAL/POLICY DECISION

- Decide each product's primary/secondary category, Kids Category participation and age band before completing the age-rating and advertising answers.
- Approve the public-leaderboard child/privacy basis, controller/contact identity, retention and deletion handling, cross-border/service-provider wording, and the exact website policy replacement.
- Decide whether Google Mobile Ads is permitted for each product and jurisdiction. Keep every ad gate `NO` until that decision and real iOS IDs exist.
- Review the Modern Ping Pong purchase/ads flow for the chosen App Store category; its approved development configuration uses test ads, and production ads remain disabled.
- Approve notification cadence/copy and whether the existing external terms URL is suitable or Apple's standard EULA should apply.
- Resolve the administrator's permitted legacy leaderboard archive/retention policy before the cutover; do not expose archived free-text aliases to active clients.

## MAC/XCODE REQUIRED

1. Regenerate the Xcode project with the pinned XcodeGen contract and inspect every target's bundle ID, Info.plist, resources, dependency graph, App Attest entitlement, signing settings, version/build and privacy manifest.
2. Run the manual four-product Simulator gate: all builds, ProductConfigurationTests exactly once, install/launch/process survival, screenshots, logs, crash reports and artifact review.
3. On physical supported devices, verify App Attest token issuance, anonymous Auth, Firestore list/write/retry/delete behavior after the identity/rules migration, offline recovery, Parent controls, and that local names never appear remotely.
4. Test StoreKit with StoreKit configuration/Sandbox/TestFlight: price load, grown-up gate, purchase, cancellation, pending, refund/revocation where available, restore after reinstall/device change, one transaction observer, and immediate ad suppression.
5. If ads are enabled, use development test mode only for test builds; verify production configuration contains real IDs, child/under-age/G/non-personalized request state, cadence, fail-closed behavior and Remove Ads suppression. Review Google SDK privacy manifests in the archive.
6. Verify local-notification prompt context, weekly schedule, cancellation, locale reschedule, denied/revoked handling and absence of remote-push entitlements on device.
7. Complete iPhone/iPad portrait/landscape visual and interaction QA, Dynamic Type, VoiceOver, Switch Control, Reduce Motion, RTL/LTR, speech/audio, memory/performance/offline, upgrade/reinstall, and native-language/linguistic review.
8. Produce App Store screenshots from the approved runtime build, archive each product, inspect archive validation and aggregate privacy reports, upload to TestFlight, complete internal/external device QA, then submit only after every owner/legal gate is resolved.

## Modern Ping Pong runtime gate

Run the additional checklist and commands in [modern-pong-ios-handoff.md](modern-pong-ios-handoff.md), including an iOS/Android same-room match in both authority directions. No Apple build, XCTest, Simulator or physical-device verification was possible on the Windows implementation host.

## 2026-09-28 Retro follow-up

`MinikRetroPingPong` (Minik Bounce) is a fifth launch scheme, with the bundle ID `com.appsbybros.minik.bouncelearn` (as on Android) and the same `RetroPongView` used in Math. Register/sign it before distribution. It needs no Firebase. Since 2026-10-01 it matches Android Bounce: an interstitial after a finished game (its own AdMob app), and a "For parents" link on setup that opens the grown-up gate before Remove Ads and Restore, so App Store Connect needs a `remove_ads` non-consumable for it too.

Math now includes the shared Modern assets and the offline Retro folder. Its two Pong routes use current Modern Simple and Retro respectively; the former legacy Pong ad callback is no longer invoked there. Math education/progress and Parent commerce remain unchanged. Existing Modern standalone Debug test ads/StoreKit source are unchanged.

Run manual `Retro Pong Simulator Verification` for the new standalone target, Math compile, native test suite and initial English/Hebrew screenshots. The existing four-product workflow is unchanged and still covers the other products. Neither workflow was dispatched in this unit. Detailed Apple playtesting gates: `docs/retro-pong-ios-handoff.md`.
