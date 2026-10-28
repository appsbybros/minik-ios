# App Store screenshots

Framed, captioned screenshots at Apple's required sizes, made from real iOS Simulator captures of the apps
(never from Android screenshots):

| Device slot in App Store Connect | Portrait | Landscape |
|---|---|---|
| iPhone 6.9" | 1320 × 2868 | 2868 × 1320 |
| iPad 13" | 2064 × 2752 | 2752 × 2064 |

Apple scales these down for smaller devices, so no other sizes are needed.

## Make them

1. GitHub → Actions → **App Store screenshots** → Run workflow.
   - **products**: the apps, separated by spaces. The default lists every app except Minik Ping Pong (on hold;
     name `MinikPingPong` to include it). An app marked `"hooks": "pending"` in `appstore/screenshots.json` (its
     scene hooks not in the app yet) is skipped with a warning; every app has its hooks now.
   - **languages**: `all` (every language each app ships) or e.g. `en he`.
2. A plan job splits the apps into product groups (`groups` in the config); each group is its own macOS job, so
   every job stays well inside the 120-minute limit. Each job builds Debug Simulator apps (no ads, no purchases),
   opens each scene on an iPhone Pro Max and an iPad Pro 13-inch Simulator in every language with a 9:41 status
   bar, and captures it.
3. The compose job frames every capture and **validates** it: exact slot size, PNG (or JPEG if a PNG would pass
   7 MB), RGB with no alpha, sRGB, 1–10 per slot and language, under 8 MB. Any problem fails the run and is listed.
4. Download the **AppStore-screenshots** artifact, ready for upload:
   `<App>/<App Store locale>/<iphone-6.9|ipad-13>/NN-scene.png`, plus `index.html` to preview them all.
   **AppStore-raw-&lt;group&gt;** holds the unframed captures and build logs.

To re-frame without a new capture (e.g. after editing a caption), download the raw artifacts into one folder and
run locally (Windows too):

```
python Scripts/appstore-screenshots.py compose --raw <raw artifacts>/appstore-raw --out build/AppStore-screenshots --apps MinikAmudu
python Scripts/appstore-screenshots.py validate --out build/AppStore-screenshots --apps MinikAmudu
python Scripts/appstore-screenshots.py check
```

This needs Pillow (`python -m pip install --user pillow`) and Chrome or Edge (set `CHROME` to pick one).

## Edit

Everything lives in `appstore/screenshots.json`:

- **Captions**: `[eyebrow, title, subtitle]` for every language the app lists. Do not write "for kids" or
  "for children": Apple reserves those words for apps in the Kids category. `check` reports a missing caption.
- **Languages and locales**: `locales` maps each language to its App Store Connect folder (`en-US`, `he`, `ar-SA`,
  `es-ES`, `hi`, `nl-NL`) and the Simulator's `-AppleLocale`.
- **Scenes**: `scene` is passed to the app as `-MinikScreenshotScene`. `wait` is seconds before the capture.
  - Minik apps: `home`, `opening`, `progress`, `parents`, `language.<activity>`, `math.<activity>`.
  - Minik Math: `web.quiz|choose|result|train|madness` (`Sources/MinikMathWeb/MinikMathWebScreenshot.swift`; a
    seeded `Math.random`, Ping Pong progress staged in memory; the web files stay identical to Android's).
  - Bounce: `bounce.setup|play|train|help`. Ping Pong: `pong.play|guide|rival`.
  - Multi Ping Pong: `multi.teams` (a seeded local 2-on-2 team match with house players; an opponent serves first),
    `multi.journey` (the daily skill journey page), `multi.avatar` (the home page's profile editor scrolled to the
    avatar choice), `pong.play` (the four-player table, without the first-visit tour), `pong.guide` (Minik's tour)
    and `home` (`MultiPong/MPStoreScreenshots.swift`, `MPController`, `ModernPongView`).
  - Spud: `spud.park|beach|andromeda|night` (a seeded six-player match with house players: the player throws and
    calls Minik), `spud.setup|home|journey|colors` (`Amudu/UI/StoreScreenshots.swift`, `AppModel`).
  - Squash / Beach Volleyball: `squash.rally|question|learn|colors|cup|home`,
    `volley.rally|park|beach|learn|team|colors` (`Sports/App/SportsScreenshots.swift`, `SportsController`).
    Rallies are seeded house-player matches; `squash.question` waits at the serve with the question open.
  - Minik Splash: `splash.beach|teams|andromeda|paint` (seeded house-player battles on the 40 x 24 court, caught
    while everyone answers and throws: beach six-player solo, park 3 x 3 teams, Andromeda six-player solo, Paint walls
    2 x 2 on the beach), `splash.play` (the Play page with Paint walls 2 x 2, so the hit rule shows) and `home`
    (`Splash/App/SplashScreenshots.swift`, `SplashController`). In a captured battle the player's avatar plays as a
    house player too, like Android's qaDemo exhibitions.
  - Triple Shot: `tripleshot.team|oneOnOne|horse|roster|league|journey` and `home`
    (`TripleShot/App/TripleShotScreenshots.swift`, the role of Android's TripleShotQaActivity): a 3 x 3 team match and
    a 1v1 at seed 31337 with fixed characters, HORSE held at the aiming arc after the right answer, the Play vs bot
    roster, a saved Court Stars League season five games in (the house results come from the league's own
    simulation) scrolled to the table, and the daily journey's three-player stage on court. The scenes press the app's
    own buttons. Every capture keeps its settings in a separate defaults suite emptied at launch, never the player's
    own, and leaves Firebase unconfigured.
- **Orientation**: per scene or per app, a string or `{"iphone": …, "ipad": …}`. Landscape captures are taken in
  landscape-right and turned upright by the compose step.
- **Groups**: which apps share a capture job. **Palettes**: background gradient and text colors per app.

The app hooks act only when the launch argument is present, which never happens for users. Spud, Splash, Multi
Ping Pong, Triple Shot and the sports apps start each capture from a fresh install's settings; their staged points and cup are
written only during a capture and removed by the next one. Matches are local and offline, with house players.

## Upload

App Store Connect → the app → the version page → **Previews and Screenshots** → pick the language at the top right →
drag the `iphone-6.9` images into the 6.9" slot and the `ipad-13` images into the 13" slot. Up to 10 per slot; the
first three show in search results.

Or let the **App Store metadata** workflow upload them with the store texts in `appstore/metadata`: give it this
run's ID as `screenshots_run_id` (it replaces each language's screenshots per slot, in file-name order, and never
submits for review). Start it with `dry_run` on first; see `Scripts/appstore-metadata.py`.

The Heebo font (`appstore/fonts`) is under the SIL Open Font License (`OFL-Heebo.txt`).
