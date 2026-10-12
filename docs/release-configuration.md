# Minik iOS release configuration

This inventory records the established values recovered from the Minik
workspace and the smaller set that is genuinely unavailable in source or Git
history. Checked-in defaults remain safe for unsigned Simulator development.

## Build metadata and bundle identifiers

The Android production flavors establish these Language identities and release
version:

| Target | Build setting | Checked-in value | Evidence |
| --- | --- | --- | --- |
| MinikPlus | `MINIK_PLUS_BUNDLE_IDENTIFIER` | `com.appsbybros.minik.plus` | canonical production Apple identifier |
| MinikPlusEnglish | `MINIK_PLUS_ENGLISH_BUNDLE_IDENTIFIER` | `com.appsbybros.minik.plus.english` | canonical production Apple identifier |
| MinikMathPlus | `MINIK_MATH_PLUS_BUNDLE_IDENTIFIER` | `com.appsbybros.minik.math.plus` | the original iOS math app, renamed Minik Math Plus like its Android twin (12 October 2026) |
| MinikMath | `MINIK_MATH_BUNDLE_IDENTIFIER` | `com.appsbybros.minik.math` | Android Minik Math's application ID; Android's web app in an iOS host (`docs/minik-math-ios.md`) |
| MinikPingPong | `MINIK_PING_PONG_BUNDLE_IDENTIFIER` | `com.appsbybros.minik.pingpong` | canonical production Apple identifier |
| ProductConfigurationTests | `MINIK_TESTS_BUNDLE_IDENTIFIER` | `com.appsbybros.minik.tests` | canonical Apple test-bundle identifier |

These identifiers are Apple-only. The Android application IDs remain unchanged.
XcodeGen writes each generated app Info.plist and Xcode supplies
`CFBundleIdentifier` from the target's routed `PRODUCT_BUNDLE_IDENTIFIER`.

`MINIK_MARKETING_VERSION=1.7.9` and `MINIK_BUILD_NUMBER=79` match the Android
`versionName` and `versionCode`. App Store Connect can override them when its
independent version history requires another value. The checked-in strategy is
one repository marketing version/build applied to all four targets: increment
the build for every upload, and introduce a per-target marketing version only
if the four App Store histories require divergence.

The Language targets use production-derived, opaque 1024-by-1024 icon compositions from
their owning Android adaptive-icon foreground/background pairs. Their exact
source paths and deterministic reproduction command are in
`docs/app-icon-provenance.md`. Modern Ping Pong now uses `ModernPongAppIcon`, a 1024px opaque composition from its current Android artwork. The Math icon configuration is unchanged by this Modern-only update.

## Firebase records

Firebase is an existing backend, not a new external project. All five checked-in
Android `google-services.json` files identify project `easycallandanswer`,
project number `497753657911`, and storage bucket
`easycallandanswer.firebasestorage.app`. They register the known Android apps;
their API keys are intentionally not copied into documentation or iOS source.

The Android records contract uses anonymous Firebase Auth for backend access,
while a separately persisted opaque UUID is written as public `player_id`. The
secure iOS target preserves that separation with a new per-product/per-profile
`v2_<UUID>` and privately binds it to the anonymous UID through
`leaderboard_owners/{player_id}`. One UID can own multiple profile IDs; the UID
does not replace `player_id`, is never public, and neither value is derived from
the local child name. A public identity is selected only from app-owned adjective +
noun + number aliases and an optional curated avatar, then persisted per local
product/profile scope. A qualifying best candidate remains local until a
curated alias is selected after the first qualifying score. Alias selection
activates participation and immediately attempts to publish the pending candidate;
later qualifying records reuse the same alias. Parent Area can change the alias
only through another generated curated choice and retains a persistent
On/Off preference; disabling stops uploads immediately, and a direct action deletes
the participant's public score/streak documents without changing local
progress. The existing Firestore contract remains:

- app ID `3`;
- `score_records` or `score_records_english_only` by Language product;
- shared `correct_answers_in_row` streak records;
- `player_id`, `user_name` (curated public alias only), optional `avatar_id`,
  `score`, `correct_answers_in_row`, and the legacy `date_achived` spelling;
- top-20 queries and atomic score/streak writes.

The complete data boundary and participation lifecycle are documented in
`docs/public-leaderboard-privacy.md`; the exact Android/iOS paths, query and
write behavior, and ownership Rules are in `docs/firebase-leaderboard-contract.md`.
The selected archive/clear cutover and updated Android contract are in
`docs/firebase-leaderboard-migration.md`.

MinikPlus and MinikPlusEnglish link the Language Firebase services. Their provided production
Apple client configurations are checked in at:

- `Config/Firebase/MinikPlus/GoogleService-Info.plist` for
  `com.appsbybros.minik.plus`;
- `Config/Firebase/MinikPlusEnglish/GoogleService-Info.plist` for
  `com.appsbybros.minik.plus.english`.

Each target's `MINIK_FIREBASE_PLIST_PATH` points only to its matching file. The
pre-build injection lints that plist, reads `BUNDLE_ID`, rejects a mismatch with
the target's `PRODUCT_BUNDLE_IDENTIFIER`, and only then copies it to the built
app as `GoogleService-Info.plist`. Math does not link Firebase or receive a plist. Modern Ping Pong separately links Auth/RTDB and directly bundles its matching `Config/Firebase/MinikPingPong/GoogleService-Info.plist`. The existing single guarded Language `FirebaseApp.configure`
path remains unchanged. Each Language target also links `FirebaseAppCheck`,
uses `Resources/Entitlements/MinikLanguage.entitlements`, and configures App
Check before that single Firebase initialization: App Attest in non-DEBUG
builds and Firebase's debug provider only inside `#if DEBUG`. No debug token is
checked in. Math receives neither Firebase nor App Check. Modern Ping Pong uses the named Firebase app `minik-ping-pong-ios` in project `minikswish`, separate from the Language Firebase app, without changing Language App Check.

Repository-owned `firestore.rules`, `firestore.indexes.json`, and
`firebase.json` now describe the strict target state. They must **not** be
deployed against legacy data/clients: historical UUIDs have no cryptographic
owner and legacy Android still accepts a free-text `user_name`. Updated iOS
source now creates only unclaimable versioned identities plus private immutable
ownership bindings; Android requires the documented equivalent. An administrator
must export/archive and verify the legacy data, clear the three active collections,
then deploy the strict Rules/indexes and coordinate updated clients. Anonymous
Auth must be enabled in Firebase Console. Both Apple apps must be registered with App
Attest, metrics must be monitored across every legitimate Android and Apple
client, and App Check enforcement must remain off until that evidence is clean.

## StoreKit

Android production declares `remove_ads` as the one-time Remove Ads product.
`MINIK_REMOVE_ADS_PRODUCT_IDENTIFIER` therefore defaults to `remove_ads` for
all targets compiling the shared commerce layer. AppStoreCommerceKit retains
the entitlement, restore, pending, cancellation, and error boundaries already
covered by its local and native-host tests. One app-root startup creates one
controller/update listener; foreground refresh and explicit restore reconcile
the authoritative entitlement, and unavailable StoreKit fails safely.

MinikPlus, MinikPlusEnglish and MinikMathPlus expose purchase/restore in Parent
Area behind the grown-up gate. MinikMathPlus can show ads only through its included
Ping Pong activity, so Remove Ads remains meaningful if that placement is
enabled. MinikMath exposes purchase/restore (`remove_ads_math`) on its parents page
behind the same gate, as Android Minik Math does, and shows interstitials after
finished rounds on Android Minik Math's schedule (`docs/minik-math-ios.md`). Modern MinikPingPong now exposes native purchase/restore and Apple offer-code redemption for its own `remove_ads` product. It shares the existing transaction controller; production ads remain disabled until release setup is supplied. StoreKit fixture identifiers remain test-only;
the frozen hosted grace-period workflow is not part of this gate.

## Ads

Android production uses Google Mobile Ads. The iOS project now links Google's
official Swift Package and has a production interstitial adapter with the
existing Minik cadence and Remove Ads suppression. Before SDK initialization it
requires all of the following:

- `MINIK_ADS_ENABLED=YES`;
- `MINIK_ADS_POLICY_APPROVED=YES`;
- a non-empty Apple-platform `MINIK_ADS_APPLICATION_IDENTIFIER`;
- a non-empty Apple-platform `MINIK_INTERSTITIAL_AD_UNIT_IDENTIFIER`.

The adapter configures age-restricted child treatment, a G maximum content
rating, and disabled publisher personalization. Android AdMob application and
ad-unit IDs are platform-specific and are deliberately not copied into the iOS
build. No iOS AdMob IDs or documented Kids-category approval were found, so the
safe defaults remain `NO` and empty. Runtime configuration and the Windows
audit reject Google's known sample/test publisher and example-ad identifiers,
so a Release build supplied with them remains unconfigured rather than showing
test inventory.

If ads are approved, MinikPlus and MinikPlusEnglish each need an iOS AdMob app
ID and interstitial unit ID for Language placements. MinikMath uses the iOS Minik
Math AdMob app (`ca-app-pub-6728099379581161~7244879780`), since it now owns the
Minik Math App Store record; MinikMathPlus still carries the same pair and needs
its own before release. MinikPingPong needs
its own pair before production ads are enabled. The new Modern adapter currently supports only the explicitly approved Debug Google test configuration (`MODERN_PONG_TEST_ADS=YES`); Release keeps it `NO`. Never copy Android IDs or invent Apple IDs.

## Local notifications

Learning reminders use `UNUserNotificationCenter` only. They default off,
request alert/sound authorization only when a parent enables the control, keep
one product-scoped weekly request, cancel pending and delivered copies when
disabled, repair/reschedule deterministically, and never prompt during lifecycle
synchronization. There is no Firebase Messaging dependency, remote-push
registration, `aps-environment` entitlement, or background remote-notification
mode. Standalone Ping Pong has no Parent Area reminder control and remains off.

## Privacy, support, terms, and legal identity

Existing production destinations are now the checked-in defaults:

- privacy: `https://miniklearn.com/privacy`;
- support: `https://miniklearn.com/contact`;
- terms: `https://www.easycallandanswer.com/terms.html`;
- legal notice: `© Apps by Bros. All rights reserved.`

The current public Minik site and Play listing say that the product has no
account/sign-in and collects no data. That statement is not accurate after a
child selects a public alias and participates in the Firebase leaderboard, which processes an anonymous
authentication UID plus the allowlisted public participant ID, generated alias
and optional avatar, score/streak, product/app ID, and timestamp. The local
child/profile name remains on-device and is never a remote identity or payload
field. Final Privacy Policy wording and App Store privacy answers must be
approved before enabling remote records in an App Store build.

The exact replacement copy for the website owner is
`docs/privacy-policy-website-replacement.md`. The source-derived questionnaire
facts and unresolved classifications are in
`docs/app-store-privacy-data-inventory.md`. The per-product Apple/Firebase/AdMob
handoff is `docs/apple-release-checklist.md`.

Each target bundles an app-owned `PrivacyInfo.xcprivacy`. Language manifests
describe the current Firebase record fields and app-only `UserDefaults` access;
Math remains unchanged and local-only in this inventory. Modern Ping Pong declares linked User ID and Gameplay Content for its private multiplayer functionality, not tracking. An archive privacy report must also be
checked for Firebase and Google Mobile Ads SDK manifests before submission.

## Signing and capabilities

No Apple Team ID, provisioning profile, certificate, App Store Connect numeric
app ID, URL scheme, or associated domain exists in the Minik workspace or Git
history. The only app entitlement is
`Resources/Entitlements/MinikLanguage.entitlements`, shared by MinikPlus and
MinikPlusEnglish for the production App Attest environment. Reminders are
local, StoreKit needs App Store Connect configuration rather than another
capability entitlement, and speech is synthesis/playback only. Do not add push
notifications, App Groups, iCloud, associated domains, or Sign in with Apple
without a feature that requires them.

The generated Info.plists currently declare no URL schemes. Only the two
Language targets use the App Attest entitlement described above. Anonymous
Firebase Auth, the `remove_ads` StoreKit product identifier, and the injected
Google Mobile Ads application/ad-unit IDs do not derive their values from the
old bundle identifiers. `remove_ads` therefore remains unchanged.

## Remaining release gates

Before archive/TestFlight submission:

1. register all four canonical App IDs with the Apple Developer account and
   create or reconcile their App Store Connect app records;
2. verify the two configured Language Apple apps in the intended Firebase
   project and review Firebase API-key restrictions/service enablement;
3. review the current app icons, including the new Modern Pong Android-derived icon;
4. select the Apple team/profiles and reconcile App Store Connect version/build
   history;
5. decide whether Google Mobile Ads is approved, then register/update each iOS
   app with its canonical bundle ID and provide iOS IDs, or leave ads disabled;
6. configure the existing `remove_ads` non-consumable for each shipping App
   Store record without renaming the product identifier;
7. enable Anonymous Auth; complete the coordinated participant-ID/Android alias
   migration; emulator-test and then deploy Firestore rules/indexes;
8. register App Attest for both Apple Language apps, monitor all Android/Apple
   clients, and only later decide whether App Check enforcement is safe;
9. approve and publish the conditional leaderboard privacy disclosures, data
   retention/deletion terms, and applicable parent-consent wording;
10. build/test/archive all four products on macOS and review the aggregate
   privacy report, device behavior, screenshots, and store metadata.

## Modern Ping Pong — 2026-09-28 source update

Apple Firebase registration `1:12298786440:ios:bfc268456a87978e75f13d` was created in `minikswish` for `com.appsbybros.minik.pingpong`. The client uses `https://minikswish-default-rtdb.europe-west1.firebasedatabase.app/` and writes only `minikPingPong/`. This does not deploy RTDB rules or change TripleShot/Language data. Full/Simple entry points, current verification evidence and all remaining Apple runtime steps are documented in [modern-pong-ios-handoff.md](modern-pong-ios-handoff.md). Existing Math and 80s routing/gameplay remain unchanged.
