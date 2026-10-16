# Minik Maze for iOS

Minik Maze is a Godot 4.7.2 game. Android runs it inside a small native host (C:\Projects\MinikMaze,
`app/src/main/assets` plus `MazeServices.kt`). iOS runs **the same Godot project**, exported with Godot's own iOS
template. The game itself is copied, not rewritten.

| Folder or file | What it is |
|---|---|
| `game/` | The Godot project. Everything outside `game/ios/` and `game/export_presets.cfg` is copied from Android by `Scripts/sync-maze-from-android.py`. |
| `game/ios/maze_services_ios.gd` | The iOS stand-in for Android's `MazeServices` plugin, registered as the same `MazeServices` engine singleton. |
| `game/ios/privacy/` | The privacy page in the game's 7 languages, with the iOS facts (App Store, no online records). |
| `game/export_presets.cfg` | The iOS export preset: `com.appsbybros.minik.maze`, version 1.4.2 (Android's versionName), iPhone and iPad, icon `game/ios/icon-1024.png` (Android's icon master). |
| `native/` | `MazeStoreKit`, the App Store purchase (StoreKit), as a godot-cpp library. |
| `build-ios-project.sh` | macOS only. Downloads Godot 4.7.2 (SHA-512 checked), builds `native/`, and exports `build/maze/MinikMaze.xcodeproj`. |
| `android-source.json` | The Android Maze and family-services commits the copy was taken from, and every copied file's hash. |

## What iOS does like Android

- The whole game: the 100 stages, both modes, questions, Lumi, Explorer Fox, balloons, saves and records on the device.
- The first 12 levels are free. One permanent purchase, `full_game_unlock`, unlocks the rest. "Restore purchases" is there.
- No ads. A grown-up gate (a multiplication, as Android's `FamilyAdultGate`) comes before the grown-up area, learning
  settings, the purchase and every outside link.
- More Minik apps shows one family app from the shared catalogue, as the Swift apps do (no Google Play link).
- The Home Screen name is "מיניק במבוך" on Hebrew devices and "Minik Maze" elsewhere.

## What iOS does differently

- **Online records:** not on iOS. The Maze brief keeps them Android-only (FEATURE_MATRIX.md: "Intentionally excluded by
  brief"). The sync script makes world.gd show the records buttons only when the platform has `load_records`, which
  the iOS services don't.
- **Ownership:** Android asks Google Play at every start. iOS keeps the unlock on the device and listens to the App Store.
  "Restore purchases" asks again, and if the App Store reports no unlock, the unlock is removed, as on Android.
- **The family catalogue:** iOS uses the copy inside the app and downloads nothing.
- **The privacy page:** an iOS version of Android's text (iPhone and iPad, App Store, no online records, no Android backup).
- **The test-level tool:** off, as in Android release builds.

## Updating from Android

```
python Scripts/sync-maze-from-android.py
```

This copies the committed Android files again and stops when an iOS change no longer fits a changed Android file.
Commit the result. The next release run uploads Minik Maze because files under `Maze/` changed.

## Building

The TestFlight and Compile Check workflows run `bash Maze/build-ios-project.sh <team ID> <build number>`, then archive
`build/maze/MinikMaze.xcodeproj` (scheme `MinikMaze`) like the other apps. Godot can also export the Xcode project on
Windows (the preset already has "project only"), but only macOS can build the StoreKit library and the app.

Before the first upload, in App Store Connect:

1. Run the "App Store Connect setup" workflow once. It registers the App ID `com.appsbybros.minik.maze`.
2. Create the app record "Minik Maze" with that bundle ID.
3. Under In-App Purchases, create the non-consumable `full_game_unlock`.
4. Remove `MinikMaze` from `WAITING` in `public-export/release_ios.py`.
