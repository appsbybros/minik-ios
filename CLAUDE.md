# Minik iOS apps (ios-qa)

iOS ports of the Android Minik apps. Each iOS app must behave exactly like its Android app; a missing Android
behaviour is a bug to fix. The only exceptions are the deliberate differences written below and in each app's
`docs/*-ios-handoff.md`. A sync from Android never removes them.

## Deliberate differences that a sync from Android must never overwrite

### Minik Amudu (Spud): its own payment model, no ads
Android Spud has ads and a "Remove ads" purchase. iOS Spud has **no ads** and instead sells one non-consumable
purchase, `com.appsbybros.minik.spud.full_game` (Family Sharing on), with a free tier:
- up to 3 players in a game (bots or people); more needs the purchase;
- the Sunshine Park arena only; the other arenas need the purchase;
- the Soft foam and Beach ball balls only; the others need the purchase, except the paint balloon below;
- the paint balloon: 3 free games to start, then 1 free game a day (counted per game, never per throw);
- the first 7 daily challenges; the rest need the purchase;
- online rooms: only the host needs the purchase. The host's choices (players, arena, ball) apply to everyone in
  the room, so joiners never pay, and a room opened from Android is never limited.

The code is in `Amudu/Store/` (no Android file maps to it), and `Tests/AmuduTests/SpudAccessTests.swift` pins every
limit, so the iOS Compile Check fails if a sync breaks the model. When porting Android's monetization changes
(`monetization/*`, AdMob, Remove ads, access codes), do not port them to iOS Spud; record them in
`docs/amudu-ios-handoff.md` under the deliberate differences instead.

## Working rules
- Translate every user-visible text into all the app's languages; never leave English-only texts on iOS.
- There is no Swift compiler on the Windows machine. GitHub's iOS Compile Check (Xcode 27 runner `xcode-27`) is
  the build check; start it or `public-export/release_ios.py` only when the owner asks.
- Builds for App Store Connect must use Xcode 27 or later (ITMS-90725); `testflight.yml` refuses older Xcode.
