# App icon provenance

The two Language app icons are deterministic compositions of the existing
production Android adaptive-icon assets. No replacement branding or generated
artwork is used.

| iOS set | Android source contract |
| --- | --- |
| `MinikPlusAppIcon` | see "Minik Plus rainbow icon" below |
| `MinikPlusEnglishAppIcon` | the former Minik Plus icon, which English Only keeps: `app/src/plus-english-only/res/mipmap-anydpi-v26/ic_launcher.xml`, `minik_plus_logo_small.png` over `bg_colorful_back_for_logo.xml` (`#DAE2E1`) |

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

## Minik Plus rainbow icon (14 October 2026)

Android Minik Plus moved its launcher to the rainbow unicorn cat on cyan in `8b1b1d6` ("Refresh Minik Plus
branding", 9 October); the `plus-english-only` flavour kept the former icon. `MinikPlusAppIcon` is
`C:/Projects/Minik/play-store/current/sources/launcher-text-free.png` (1254 x 1254, SHA-256 begins
`98da8992cc8fc03d`), the full-square art behind Android's `launcher_rainbow_foreground` over
`#2EC8F2`, scaled to 1024 x 1024, RGB. `MinikPlusEnglishAppIcon` now holds the former
`MinikPlusAppIcon` image, and the `MinikPlusEnglish` target uses it.
