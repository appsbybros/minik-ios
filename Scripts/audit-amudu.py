#!/usr/bin/env python3
"""Static parity audit of the Spud (Amudu) iOS port against the Android project.

Read-only for both trees. Checks:
  1. Every user-visible / protocol string literal in the Android Kotlin sources also appears in the Swift sources
     (interpolations normalized), except the documented debug/QA/ads exclusions.
  2. Amudu/Text/AmuduCatalog.json equals the Android AppText catalog (order, keys, four columns).
  3. GameText overrides are identical.
  4. Every image/audio/JSON asset the Swift code loads exists in Amudu/.
  5. Swift hygiene: one @main, LF endings, balanced braces/parentheses outside strings and comments, no `try!`.
  6. Prints the SHA-256 of every Android file the port used (--hashes) for docs/amudu-ios-handoff.md.

Usage: python Scripts/audit-amudu.py [--android C:/Projects/MinikAmudu] [--hashes]
"""
import argparse
import hashlib
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IOS = os.path.join(ROOT, "Amudu")
TESTS = os.path.join(ROOT, "Tests", "AmuduTests")

KOTLIN_SOURCES = [
    "app/src/main/java/com/appsbybros/minik/amudu/AmuduActivity.kt",
    "app/src/main/java/com/appsbybros/minik/amudu/AmuduView.kt",
    "app/src/main/java/com/appsbybros/minik/amudu/ArtStore.kt",
    "app/src/main/java/com/appsbybros/minik/amudu/Codec.kt",
    "app/src/main/java/com/appsbybros/minik/amudu/GameText.kt",
    "app/src/main/java/com/appsbybros/minik/amudu/OnlineRoom.kt",
    "app/src/main/java/com/appsbybros/minik/amudu/SelectionWidgets.kt",
    "app/src/main/java/com/appsbybros/minik/amudu/core/AmuduEngine.kt",
    "app/src/main/java/com/appsbybros/minik/amudu/core/Models.kt",
    "app/src/main/java/com/appsbybros/minik/amudu/core/ProgressRanks.kt",
    "app/src/main/java/com/appsbybros/minik/amudu/HebrewStopCalls.kt",
    "app/src/main/java/com/appsbybros/minik/amudu/PictureChoices.kt",
    "app/src/main/java/com/appsbybros/minik/amudu/RuleText.kt",
    "app/src/main/java/com/appsbybros/minik/amudu/SnapshotGuard.kt",
    "app/src/main/java/com/appsbybros/minik/amudu/StopCallVoice.kt",
    "app/src/main/java/com/appsbybros/minik/amudu/JourneyCelebration.kt",
    "app/src/main/java/com/appsbybros/minik/amudu/core/SpudJourney.kt",
    "app/src/main/java/com/appsbybros/minik/world/SpudReceptionZoom.kt",
    "app/src/main/java/com/appsbybros/minik/ui/CenteredToggleSpan.kt",
    "app/src/main/java/com/appsbybros/minik/ui/GameDialogBuilder.kt",
    "app/src/main/java/com/appsbybros/minik/world/ArenaCamera.kt",
    "app/src/main/java/com/appsbybros/minik/world/ArenaWorldView.kt",
    "app/src/main/java/com/appsbybros/minik/world/LandscapeFraming.kt",
    "app/src/main/java/com/appsbybros/minik/world/SpriteSizing.kt",
    "app/src/main/java/com/appsbybros/minik/world/StableLabels.kt",
]

# Android-only literals: debug QA intents/files, ads/billing/parent gate, Android framework identifiers.
EXCLUDED_SUBSTRINGS = [
    "qa", "QA", "amudu_visual_qa", "Ads & purchases", "Test ads only", "Purchases and codes", "Remove ads", "Ads removed",
    "Restore purchase", "Enter code", "Your Amudu code", "For a grown-up", "Try again.", "Apply", "unconfigured", "purchased",
    "ready\"", "emulator", "1:1234567890", "demo-minik-amudu", "firebaseio", "127.0.0.1", "sans-serif", "art/", ".webp",
    "tennis.png", "Missing ", "amudu_ads", "frequency", "Amudu code", "Code copied", "$a × $b",
    # The OpenGL ES world shaders are ported to Metal Shading Language (Amudu/World/ArenaWorldView.swift).
    "gl_Position", "gl_FragColor",
]
# Literals whose behavior the Swift code reproduces without the same literal (documented in the handoff):
# Hebrew ads/billing/parent-gate texts (feature off on iOS), the debug demo name, regexes replaced by Unicode-category
# checks, path templates built by concatenation, the layout-cache key and the tag text built with " · ".
EQUIVALENT = {
    "Player", "פרסומות ורכישות", "[A-Z2-9]{6}", "Android compatibility", "פרסומות בדיקה רק אחרי משחקים שהסתיימו.",
    "רכישות וקודים דורשים הפעלה בחנות.", "הסרת פרסומות · ", "הפרסומות הוסרו.", "הסרת פרסומות", "שחזור רכישה", "הזנת קוד", "אישור",
    "למבוגר אחראי", "{} × {} = ?", "נסו שוב.", "{}/{}/{}/{}", "{} · {}", "own", "running", "meanFrameMs", "screen", "origin",
    "width", "hands", "UNCHECKED_CAST", "minikAmudu/rooms/{}", "members/{}", "commands/{}",
    "House players must have unique avatars, distinct from humans.", r"[\p{L}\p{M}\p{N}]+", r"[\p{L}\p{M}\p{N} '\-]+", r"\s+",
    # Android accessibility class name: iOS marks the picture choices with the selected button trait.
    "android.widget.RadioButton",
    # OpenGL attribute/uniform names: Metal binds the same values by buffer index.
    "aPos", "aUv", "uMode", "uAlpha", "uTex", "uCamera", "uLens", "uCenterX", "uCenter", "uTime", "uNight", "uScene", "uBounds",
    # World art Android loads but never draws in this (non-Pro) edition; not bundled on iOS. iOS names the three skies
    # in full ("park_sky", ...) instead of joining scene + "_" + "sky".
    "heroes", "barriers", "scenes", "micro", "gloss", "urban", "parking", "building", "sky",
    # The family module (com.appsbybros.family, MinikFamilyServices) is Android-only: "More Minik apps", public rooms,
    # and the "Return to room" prefix FamilyMenu uses to file "Return to room (CODE)" (iOS builds that button directly).
    "More Minik apps & games", "עוד אפליקציות ומשחקי מיניק", "Public rooms & championships", "חדרים פתוחים ואליפויות",
    "Return to room", "חזרה לחדר",
    # Settings & feedback: Android shares and rates its Play listing through an Intent chooser; iOS shares the game's
    # public page with the system share sheet (no chooser title) and asks the App Store for its rating prompt.
    "https://play.google.com/store/apps/details?id={}", "text/plain", "Share", "שיתוף",
    # Android help passes "\\n" (a visible backslash and n, so no translation matches); iOS shows the line break the
    # game screen uses for the same text.
    "Drag to run · Tap / hold to catch\\nDouble-tap to duck", "גררו כדי לרוץ · נגיעה או לחיצה לתפיסה\\nנגיעה כפולה להתכופפות",
}
EXCLUDED_EXACT = {
    "", " ", "amudu", "saved", "room", "name", "avatar", "scene", "ball", "freeze", "count", "turns", "house", "daylight",
    "throwMode", "wind", "language", "{}", "hand", "rect", "frames", "characters", "front", "back", "left", "right",
    "fallback", "house", "-", "/", "?", "en", "he", "frog", "banana", "say", "renamed", "call", "freeze", "selected",
    "Online activation is pending.",
    # Preference names: iOS keeps them in UserDefaults with this app's "amudu." prefix.
    "ruleSet", "ruleConfig_", "ruleHouse_", "colourPoints", "rankReceipts", "skillJourney", "practiceSaved",
    "receptionZoomOwn", "receptionZoomOthers", "gameSounds", "battleOrientation",
    # Android view tags and QA control names (device tests only).
    "receptionZoomGroup", "group_", "arena_choices", "ball_choices", "choice_", "rotate", "roster", "camera", "chat",
}


def decode_kotlin(src, i):
    """Parse a Kotlin "..." literal at src[i]. Returns (text with {} for templates, next index)."""
    assert src[i] == '"'
    i += 1
    out = []
    while i < len(src):
        ch = src[i]
        if ch == '"':
            return "".join(out), i + 1
        if ch == "\\":
            nxt = src[i + 1]
            mapping = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "'": "'", "\\": "\\", "$": "$", "b": "\b"}
            if nxt == "u":
                out.append(chr(int(src[i + 2:i + 6], 16)))
                i += 6
                continue
            out.append(mapping.get(nxt, nxt))
            i += 2
            continue
        if ch == "$" and i + 1 < len(src) and src[i + 1] == "{":
            depth = 0
            j = i + 1
            while j < len(src):
                if src[j] == "{":
                    depth += 1
                elif src[j] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            out.append("{}")
            i = j + 1
            continue
        if ch == "$" and i + 1 < len(src) and (src[i + 1].isalpha() or src[i + 1] == "_"):
            j = i + 1
            while j < len(src) and (src[j].isalnum() or src[j] == "_"):
                j += 1
            out.append("{}")
            i = j
            continue
        out.append(ch)
        i += 1
    raise ValueError("unterminated Kotlin string")


def decode_swift(src, i):
    """Parse a Swift "..." literal at src[i]. Returns (text with {} for interpolations, next index)."""
    assert src[i] == '"'
    i += 1
    out = []
    while i < len(src):
        ch = src[i]
        if ch == '"':
            return "".join(out), i + 1
        if ch == "\n":
            return "".join(out), i
        if ch == "\\":
            nxt = src[i + 1]
            if nxt == "(":
                depth = 0
                j = i + 1
                in_string = False
                while j < len(src):
                    c = src[j]
                    if c == '"':
                        in_string = not in_string
                    elif not in_string and c == "(":
                        depth += 1
                    elif not in_string and c == ")":
                        depth -= 1
                        if depth == 0:
                            break
                    j += 1
                out.append("{}")
                i = j + 1
                continue
            if nxt == "u" and src[i + 2] == "{":
                end = src.index("}", i)
                out.append(chr(int(src[i + 3:end], 16)))
                i = end + 1
                continue
            mapping = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "'": "'", "\\": "\\", "0": "\0"}
            out.append(mapping.get(nxt, nxt))
            i += 2
            continue
        out.append(ch)
        i += 1
    raise ValueError("unterminated Swift string")


def literals(path, decoder):
    src = open(path, encoding="utf-8").read()
    found = []
    i = 0
    n = len(src)
    while i < n:
        ch = src[i]
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if ch == "'":
            # Kotlin/Swift char literal or apostrophe inside code: skip simple char literals.
            if decoder is decode_kotlin and i + 2 < n and src[i + 2] == "'":
                i += 3
                continue
            if decoder is decode_kotlin and src.startswith("'\\", i):
                j = src.find("'", i + 2)
                i = j + 1
                continue
        if ch == '"':
            try:
                text, i = decoder(src, i)
            except (ValueError, IndexError):
                i += 1
                continue
            found.append(text)
            continue
        i += 1
    return found


def swift_files(*roots):
    for root in roots:
        for base, _, files in os.walk(root):
            for f in files:
                if f.endswith(".swift"):
                    yield os.path.join(base, f)


def check_strings(android):
    swift = set()
    for path in swift_files(IOS):
        swift.update(literals(path, decode_swift))
    missing = []
    for rel in KOTLIN_SOURCES:
        path = os.path.join(android, rel)
        for text in literals(path, decode_kotlin):
            if text in EXCLUDED_EXACT or text in EQUIVALENT or any(x in text for x in EXCLUDED_SUBSTRINGS):
                continue
            if len(text) <= 1:
                continue
            if text not in swift:
                missing.append((rel.split("/")[-1], text))
    unique = []
    seen = set()
    for item in missing:
        if item not in seen:
            seen.add(item)
            unique.append(item)
    return unique


def kotlin_map_pairs(src, k):
    """The `"key" to listOf("a", ...)` pairs of one Kotlin `mapOf(` call; `k` is the index just after `mapOf(`."""
    pairs = []
    while True:
        while src[k] in " \t\r\n,":
            k += 1
        if src[k] == ")":
            return pairs
        key, k = decode_kotlin(src, k)
        m = re.match(r"\s*to\s+listOf\(", src[k:])
        if not m:
            raise ValueError("unexpected AppText entry near %r" % src[k:k + 60])
        k += m.end()
        values = []
        while True:
            while src[k] in " \t\r\n,":
                k += 1
            if src[k] == ")":
                k += 1
                break
            v, k = decode_kotlin(src, k)
            values.append(v)
        pairs.append((key, values))


def kotlin_catalog(android):
    """The effective Android `AppText.rows` map: the `mapOf` functions joined with `+` in the order of the `rows`
    expression. Kotlin `+` and `mapOf` keep a key at its first position and take the last value, like a Python dict."""
    folder = os.path.join(android, "app/src/main/java/com/appsbybros/minik/localization")
    src = open(os.path.join(folder, "AppText.kt"), encoding="utf-8").read()
    expression = re.search(r"private val rows:Map<String,List<String>> by lazy \{([^}]*)\}", src)
    names = re.findall(r"(\w+)\(\)", expression.group(1))
    # The row functions live in AppText.kt (private) or in their own files (internal, e.g. SpudJourneyText.kt).
    sources = [open(os.path.join(folder, f), encoding="utf-8").read() for f in sorted(os.listdir(folder)) if f.endswith(".kt")]
    rows = {}
    for name in names:
        found = None
        for text in sources:
            m = re.search(r"(?:private |internal )?fun %s\(\)=mapOf\(" % name, text)
            if m:
                found = (text, m.end())
                break
        if found is None:
            raise ValueError("AppText row function %s() not found" % name)
        for key, values in kotlin_map_pairs(found[0], found[1]):
            rows[key] = values
    return [[key] + values for key, values in rows.items()]


def check_catalog(android):
    expected = kotlin_catalog(android)
    actual = json.load(open(os.path.join(IOS, "Text", "AmuduCatalog.json"), encoding="utf-8"))
    return expected == actual, len(expected), len(actual)


def overrides_from(path, decoder, start_marker):
    src = open(path, encoding="utf-8").read()
    body = src[src.index(start_marker):]
    found = literals_from_text(body, decoder)
    return found


def literals_from_text(text, decoder):
    out = []
    i = 0
    while i < len(text):
        if text[i] == '"':
            try:
                value, i = decoder(text, i)
            except (ValueError, IndexError):
                i += 1
                continue
            out.append(value)
            continue
        i += 1
    return out


def check_overrides(android):
    kotlin = overrides_from(os.path.join(android, "app/src/main/java/com/appsbybros/minik/amudu/GameText.kt"), decode_kotlin, "private val overrides")
    swift = overrides_from(os.path.join(IOS, "Text", "AppText.swift"), decode_swift, "private static let overrides")
    return kotlin == swift[:len(kotlin)], len(kotlin)


def check_assets():
    problems = []
    catalog = os.path.join(IOS, "Assets.xcassets")
    names = ["miniko", "minik", "kyra", "flare", "gaya", "mia", "amber", "comet", "june", "moshiko", "coach67"]
    needed = names + [n + "_directions" for n in names] + ["park", "beach", "andromeda", "foam", "beachball", "neon", "tennis"]
    for n in needed:
        folder = os.path.join(catalog, n + ".imageset")
        if not os.path.isfile(os.path.join(folder, n + ".png")) or not os.path.isfile(os.path.join(folder, "Contents.json")):
            problems.append("missing imageset " + n)
    for f in ["sfx_throw.mp3", "bounce.wav", "ball_catch.wav", "sfx_pickup.mp3", "sfx_wrong.mp3", "whistle.wav", "sfx_finish.mp3",
              "connected.mp3", "player_ready.mp3", "amodu_call_funny.mp3", "amodu_call_standard.mp3"]:
        if not os.path.isfile(os.path.join(IOS, "Audio", f)):
            problems.append("missing audio " + f)
    for f in ["Art/atlas.json", "Art/directions.json", "Text/AmuduCatalog.json"]:
        if not os.path.isfile(os.path.join(IOS, f)):
            problems.append("missing " + f)
    for lang in ["en", "he", "ar", "es", "hi", "nl"]:
        if not os.path.isfile(os.path.join(IOS, lang + ".lproj", "InfoPlist.strings")):
            problems.append("missing " + lang + ".lproj/InfoPlist.strings")
    return problems


def strip_code(src):
    """Remove comments and string literals so brackets can be counted."""
    out = []
    i = 0
    n = len(src)
    while i < n:
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if src[i] == '"':
            try:
                _, i = decode_swift(src, i)
            except (ValueError, IndexError):
                i += 1
            out.append('""')
            continue
        out.append(src[i])
        i += 1
    return "".join(out)


def check_swift():
    problems = []
    mains = 0
    for path in swift_files(IOS, TESTS):
        raw = open(path, "rb").read()
        rel = os.path.relpath(path, ROOT)
        if b"\r\n" in raw:
            problems.append(rel + ": CRLF line endings")
        src = raw.decode("utf-8")
        code = strip_code(src)
        if path.startswith(IOS):
            mains += len(re.findall(r"^\s*@main\b", code, flags=re.M))
        for open_c, close_c in ["{}", "()", "[]"]:
            if code.count(open_c) != code.count(close_c):
                problems.append("%s: unbalanced %s%s (%d vs %d)" % (rel, open_c, close_c, code.count(open_c), code.count(close_c)))
        if "try!" in code:
            problems.append(rel + ": uses try!")
    if mains != 1:
        problems.append("expected exactly one @main in Amudu/, found %d" % mains)
    return problems


def android_inputs(android):
    files = []
    for rel in ["README.md", "DECISIONS.md", "BUILD_STATUS.md", "ASSET_MANIFEST.md", "EXTERNAL_ACTIONS_REQUIRED.md",
                "firebase/database.rules.json", "firebase/rules-test.cjs", "firebase/firebase.json", "firebase/start-emulators.ps1"]:
        files.append(rel)
    for base in ["app/src/main/java", "app/src/test/java", "app/src/androidTest/java", "app/src/main/assets/art", "app/src/main/res"]:
        for folder, _, names in os.walk(os.path.join(android, base)):
            for name in sorted(names):
                files.append(os.path.relpath(os.path.join(folder, name), android).replace("\\", "/"))
    files.append("app/src/main/AndroidManifest.xml")
    files.append("app/build.gradle.kts")
    return sorted(set(files))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--android", default="C:/Projects/MinikAmudu")
    parser.add_argument("--hashes", action="store_true")
    args = parser.parse_args()
    android = args.android
    failed = False

    ok, expected, actual = check_catalog(android)
    print("catalog: %s (android %d rows, ios %d rows)" % ("OK" if ok else "MISMATCH", expected, actual))
    failed |= not ok

    ok, count = check_overrides(android)
    print("GameText overrides: %s (%d literals)" % ("OK" if ok else "MISMATCH", count))
    failed |= not ok

    missing = check_strings(android)
    print("android literals missing from Swift: %d" % len(missing))
    for source, text in missing:
        print("  [%s] %r" % (source, text))
    failed |= bool(missing)

    assets = check_assets()
    print("assets: %s" % ("OK" if not assets else "; ".join(assets)))
    failed |= bool(assets)

    swift = check_swift()
    print("swift hygiene: %s" % ("OK" if not swift else ""))
    for p in swift:
        print("  " + p)
    failed |= bool(swift)

    if args.hashes:
        print("\nSHA-256 of Android inputs:")
        for rel in android_inputs(android):
            path = os.path.join(android, rel)
            if os.path.isfile(path):
                digest = hashlib.sha256(open(path, "rb").read()).hexdigest()
                print("| `%s` | `%s` |" % (rel, digest))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
