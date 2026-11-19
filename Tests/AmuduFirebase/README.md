# Spud (Amudu) Realtime Database rules — reference copy

Byte-identical copies of the Android project's `C:/Projects/MinikAmudu/firebase/` files. The iOS app writes the same
`minikAmudu/rooms/{CODE}` tree (and, since 2026-11-19, the family-league paths `leagues`, `leagueCodes`, `leagueUsers`,
`leagueInvites` and the opt-in `diagnostics`) as Android, so these rules govern both platforms. Never deploy from here; production
rules are merged and deployed only with the owner's separate authorization.

| File | SHA-256 |
|---|---|
| `database.rules.json` | `c80298ba1bb68ffffcb7262cca727883bb5fb87dd52895079c06d25e542abf7f` |
| `rules-test.cjs` | `867ebd57d4ee444a84d56b764d7861ead885b74483135b5a334e86aae0e7553d` |
| `firebase.json` | `8980a41bdbd7e364174987800b571acfefb536320293a4bc2fdae3d7c1510e75` |
| `start-emulators.ps1` | `28c3a00402243f93613c6d97a5eded2a27cb62ea3d243678bbc607c34c5d71f2` |

## Run offline (local database emulator only)

`rules-test.cjs` uses mock auth tokens, so only the database emulator is needed. Start the cached emulator jar directly
(no Firebase CLI, so no update checks or downloads), then run the test against it:

```sh
java -jar ~/.cache/firebase/emulators/firebase-database-emulator-v4.11.2.jar --host 127.0.0.1 --port 19006 &
AMUDU_DATABASE_PORT=19006 node Tests/AmuduFirebase/rules-test.cjs
```

The script loads `@firebase/rules-unit-testing` and `firebase` read-only from a `node_modules` folder (2026-11-19:
`NODE_PATH=C:/Projects/MinikAmudu/firebase/node_modules`; Java from Android Studio's `jbr`). Results: 2026-10-04 106 passed;
2026-11-19 (Android 372c448 rules) **196 passed, 0 failed, 0 production writes**.
