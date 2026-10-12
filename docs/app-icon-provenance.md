# App icon provenance

The two Language app icons are deterministic compositions of the existing
production Android adaptive-icon assets. No replacement branding or generated
artwork is used.

| iOS set | Android source contract |
| --- | --- |
| `MinikPlusAppIcon` | `android/app/src/plus/res/mipmap-anydpi-v26/ic_launcher.xml`: `minik_plus_logo_small.png` over `bg_colorful_back_for_logo.xml` (`#DAE2E1`) |
| `MinikPlusEnglishAppIcon` | the `plus-english-only` flavor has no launcher override, so `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`: `minik_logo333.png` over `bg_card_front_kids2.xml` (`#03A9F4` / `#3F51B5` / `#009688`) |

`Scripts/migrate-android-app-icons.ps1` performs the 1024-by-1024 opaque raster
composition used by the checked-in Xcode asset sets. Apple applies the final
platform mask; rounded corners are not baked into the source.

## Minik Math and Minik Math Plus (12 October 2026)

| iOS set | Source |
| --- | --- |
| `MinikMathAppIcon` (target `MinikMath`) | the "MINIK Math" icon; the same art as Android Minik Math's `app/src/main/res/drawable/app_icon.png` (1024 x 1024) |
| `MinikMathPlusAppIcon` (target `MinikMathPlus`) | Android Minik Math Plus's store icon master `C:/Projects/MinikMathPlus/play-store/current/sources/square-icon-master.png` (1254 x 1254, not committed there; SHA-256 begins `531675cf926d5385`), scaled to 1024 x 1024, RGB |

Earlier note (before the Math icons): no established Minik Math or standalone Minik Ping Pong App Store icon was
found in the workspace or Git history. Those two targets intentionally keep the
app-icon build setting empty rather than repurposing unrelated branding.
