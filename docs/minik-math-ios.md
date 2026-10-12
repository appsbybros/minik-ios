# Minik Math on iOS (target `MinikMath`)

Written 12 October 2026. **Not compiled or run yet**: this was written on Windows, without Xcode.

## What changed

The owner's decision of 11 to 12 October 2026:

- The original, larger iOS math app is now **Minik Math Plus**: target and scheme `MinikMathPlus`, bundle ID
  `com.appsbybros.minik.math.plus`, Remove Ads product `remove_ads_math_plus`, the Android Minik Math Plus store
  icon. Its Swift code is unchanged (`MINIK_MATH`, product variant `minikMath`).
- **Minik Math** is now Android Minik Math (`C:\Projects\minikMath`) on iOS: target and scheme `MinikMath`, bundle ID
  `com.appsbybros.minik.math` (Android's application ID, and the existing App Store Connect record), Remove Ads
  product `remove_ads_math`, the "MINIK Math" icon (Android's `app_icon.png`), English and Hebrew.

## How it is built

Android Minik Math is a web app (`app/src/main/assets/www`) in a small Java host. iOS keeps the web app and replaces
the host:

| Android | iOS |
| --- | --- |
| `assets/www` (113 files) | `Resources/MinikMathWeb`, byte-identical (Android commit `bbd9b48`, `docs/minik-math-web-manifest.json`; `.gitattributes` keeps one CRLF file as it is) |
| `MainActivity` WebView: DOM storage, sound without a tap, no overscroll, user-agent markers | `Sources/MinikMathWeb/MinikMathWebView.swift` (WKWebView, persistent website data store, inline media, mobile content mode on iPad) |
| `MonetizationBridge` (`MinikAdsNative`: `prepare`, `playing`, `settings`, `finish`) | `MinikMathWebBridge.script`, a document-start script that defines the same object and posts to the host; Android's ID and token checks |
| `trustedMoneyPage`, `pageEpoch` | `MinikMathWebPages.isTrusted`, the coordinator's `pageEpoch` |
| `AdPolicy` | `MinikMathAdPolicy.swift`, rule for rule; `Tests/MinikMathTests/MinikMathAdPolicyTests.swift` ports all 17 Android tests |
| `AdCoordinator` | `MinikMathAdCoordinator.swift`: one-second play-time tick, ad only at a finished round, "Round finished" pause of 0.7 s, results after the ad closes; the shared Google Mobile Ads service shows the ad (child-directed, non-personalized, G) |
| `MonetizationActivity` (parents page) | `MinikMathParentsView` in `MinikMathWebRootView.swift`: the shared grown-up gate, then Remove Ads, Restore and the privacy policy, with Android's texts (App Store instead of Google Play) in the web app's language |
| Landscape for embedded Ping Pong (`updateOrientationForUrl`) | `MinikMathOrientation`: landscape on iPhone; iPad keeps every orientation (the web Ping Pong plays in a portrait tablet window, as on Android 16 tablets) |
| `onPause` / `onResume` | stop sounds and pause Ping Pong when the app is not active or a sheet covers it; resume Ping Pong |
| Hidden system bars, Math and Ping Pong backgrounds | hidden status bar and home indicator; the same colours |

## Deliberate differences from Android

- **No exit button.** The web app shows its "X" only when the host sends `MinikNativeExit/1`; iOS apps do not close
  themselves, so the iOS host does not send it.
- **The web app sees Android's host marker.** The web files turn on their app behaviour (native insets, Ping Pong
  arrows and paddle ranks) only for `MinikNative/Android`, so the iOS host sends it, plus `MinikHost/iOS`. The web
  files stay unchanged.
- **Links out of the app need a grown-up.** Android opens the footer's main-site link in the browser; iOS shows the
  grown-up gate first, as Apple asks of apps for children.
- **No access codes.** On iOS only an App Store purchase may remove ads; Android's codes are not active either.
- **No consent form, no age question.** Like every iOS Minik app, every ad request is child-directed and
  non-personalized.
- **`prepare` loads nothing extra.** The shared ad service keeps one interstitial loaded (at start and after each ad).
  When none is ready at a due round, that round shows no ad and the next one tries again, as on Android.

## Updating from Android

When Android changes its web app, `Scripts/audit-minik-math-web.py` fails with "changed since". Copy the committed
files again and refresh the manifest:

```bash
git -C C:/Projects/minikMath archive HEAD app/src/main/assets/www | tar -x -C /tmp/minik-www
rm -rf Resources/MinikMathWeb && mv /tmp/minik-www/app/src/main/assets/www Resources/MinikMathWeb
```

Then update `androidCommit`, `androidTree` and `files` in `docs/minik-math-web-manifest.json` (the audit prints what
differs) and check that `minik-monetization.js` still calls the four bridge methods.

## Owner steps

1. Run **App Store Connect setup** (it registers `com.appsbybros.minik.math.plus`).
2. In App Store Connect create the app **Minik Math Plus** with bundle ID `com.appsbybros.minik.math.plus`, and its
   Remove Ads in-app purchase `remove_ads_math_plus`. The existing **Minik Math** record now receives the small app;
   its Remove Ads product is `remove_ads_math`.
3. Run **iOS Compile Check** (it also runs the Minik Math unit tests), then **TestFlight upload** with products
   `MinikMath` (and `MinikMathPlus` once its record exists).
4. Later: give Minik Math Plus its own AdMob app; until then both Math apps use the Minik Math AdMob IDs.

## Checks

- `Scripts/audit-minik-math-web.py`: the copy against the manifest and Android, and the host contract.
- `Tests/MinikMathTests`: the ported AdPolicy tests, the coordinator (free rounds, the ad before results, removed ads,
  leaving the app, duplicate rounds, play time, saving) and the bridge (Android's checks, trusted pages, the bundled
  files calling the bridge).
