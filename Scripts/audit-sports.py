#!/usr/bin/env python3
"""Offline parity audit for the Minik Squash and Minik Beach Volley iOS port (Sports/) against the
read-only Android project (default C:/Projects/MinikSports). It never writes to the Android tree and
never contacts a server.

Checks:
  catalog   Sports/Localization/apptext.json equals the effective AppText.rows catalog (order and values).
  tables    Sports/Localization/sportstext.json equals SportsText.extra, SquashText.entries,
            VolleyText.labels/tips and CourtJourneyText.rows (order and values).
  facts     Sports/Core/QuestionFacts.swift equals QuestionBank.english/world in Learning.kt.
  texts     Every English/Hebrew pair passed to tr()/AppText.t()/SportsText.t() in Sports Swift exists in
            the Android Kotlin sources (interpolations normalised), and Android pairs not used on iOS
            are listed (ads/purchases/family services are expected there).
  art       Every Sports/Assets.xcassets/Art PNG decodes to exactly the Android WebP pixels.
  files     Audio MP3s, art JSON, privacy pages and the two menu pictures (Assets.xcassets/Menu, from
            the app modules' res/drawable-nodpi) are byte-identical to Android.
  swift     Swift sources use LF line endings and contain exactly one @main.

Usage:  python Scripts/audit-sports.py [--android PATH] [--write-facts] [--write-catalog] [--hashes]
Requires Pillow for the art check.
"""
import argparse
import hashlib
import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPORTS = os.path.join(ROOT, "Sports")
TESTS = os.path.join(ROOT, "Tests", "SportsTests")
MODULE = "sports/src/main"
KOTLIN = MODULE + "/java/com/appsbybros/minik"
BS = chr(92)
ESC = {"n": "\n", "t": "\t", "r": "\r", "b": "\b", '"': '"', BS: BS, "$": "$", "'": "'"}
SOUNDS = ("ball_hit", "connected", "cool_music2", "failure_sound", "minik_kick", "minik_kick2", "player_ready",
          "success_in_a_raw_sound", "success_sound")
LANGUAGES = ("ar", "en", "es", "he", "hi", "nl")


# ---------------------------------------------------------------- Kotlin / Swift literals

def kotlin_literals(text, normalise=True):
    """Yield (start, value) for every Kotlin double-quoted string; templates become {}."""
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "/" and text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == "'" and i + 2 < n:
            # A character literal ('"', '\'', 'א') must not open a string.
            j = i + 1
            if text[j] == BS:
                j += 2 if text[j + 1] != "u" else 6
            else:
                j += 1
            if j < n and text[j] == "'":
                i = j + 1
                continue
        if c != '"':
            i += 1
            continue
        start = i
        i += 1
        buf = []
        while i < n:
            c = text[i]
            if c == BS:
                e = text[i + 1]
                if e == "u":
                    buf.append(chr(int(text[i + 2:i + 6], 16)))
                    i += 6
                else:
                    buf.append(ESC.get(e, e))
                    i += 2
                continue
            if c == "$" and i + 1 < n and text[i + 1] == "{":
                depth, i = 1, i + 2
                while i < n and depth:
                    if text[i] == "{":
                        depth += 1
                    elif text[i] == "}":
                        depth -= 1
                    elif text[i] == '"':
                        i += 1
                        while i < n and text[i] != '"':
                            i += 2 if text[i] == BS else 1
                    i += 1
                buf.append("{}" if normalise else "${...}")
                continue
            if c == "$" and i + 1 < n and (text[i + 1].isalpha() or text[i + 1] == "_"):
                i += 1
                while i < n and (text[i].isalnum() or text[i] == "_"):
                    i += 1
                buf.append("{}" if normalise else "$x")
                continue
            if c == '"':
                i += 1
                break
            buf.append(c)
            i += 1
        yield start, "".join(buf)


def swift_literals(text):
    """Yield (start, value) for Swift single-line string literals; interpolations become {}."""
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "/" and text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if c != '"':
            i += 1
            continue
        if text.startswith('"""', i):
            j = text.find('"""', i + 3)
            i = n if j < 0 else j + 3
            continue
        start = i
        i += 1
        buf = []
        while i < n:
            c = text[i]
            if c == BS:
                e = text[i + 1]
                if e == "(":
                    depth, i = 1, i + 2
                    while i < n and depth:
                        if text[i] == "(":
                            depth += 1
                        elif text[i] == ")":
                            depth -= 1
                        elif text[i] == '"':
                            i += 1
                            while i < n and text[i] != '"':
                                i += 2 if text[i] == BS else 1
                        i += 1
                    buf.append("{}")
                    continue
                if e == "u":
                    j = text.index("}", i)
                    buf.append(chr(int(text[i + 3:j], 16)))
                    i = j + 1
                    continue
                buf.append(ESC.get(e, e))
                i += 2
                continue
            if c == '"':
                i += 1
                break
            buf.append(c)
            i += 1
        yield start, "".join(buf)


def call_pairs(text, literals, names):
    """English/Hebrew argument pairs of tr(...) / AppText.t(...) calls."""
    lits = list(literals(text))
    by_start = {s: v for s, v in lits}
    starts = [s for s, _ in lits]
    pairs = set()
    for m in re.finditer(r"\b(?:%s)\(\s*" % "|".join(names), text):
        first = m.end()
        if first not in by_start:
            continue
        idx = starts.index(first)
        en = by_start[first]
        he = None
        if idx + 1 < len(starts):
            between = text[first:starts[idx + 1]]
            if re.fullmatch(r'"[\s\S]*"\s*,\s*', between) and "\n\n" not in between and between.count('"') <= 2 + between.count(BS + '"'):
                he = by_start[starts[idx + 1]]
        pairs.add((en, he))
    return pairs


# ---------------------------------------------------------------- catalogs and facts

def table_rows(body, columns=5):
    """The `"key" to listOf(...)` rows of a mapOf body (up to its closing parenthesis line)."""
    rows = []
    for line in body.split("\n"):
        if " to listOf(" not in line:
            if line.strip().startswith(")"):
                break
            continue
        values = [v for _, v in kotlin_literals(line, normalise=False)]
        if len(values) != columns:
            raise SystemExit("unexpected table line: " + line[:120])
        rows.append(values)
    return rows


def parse_catalog(android):
    """The effective Android `AppText.rows` map: the `mapOf` row functions joined with `+` in the order of
    the `rows` expression. Kotlin `+` keeps a key at its first position and takes the last value, like a
    Python dict."""
    app_text = io.open(os.path.join(android, KOTLIN, "localization/AppText.kt"), encoding="utf-8").read()
    expression = re.search(r"private val rows:Map<String,List<String>> by lazy \{([^}]*)\}", app_text)
    names = re.findall(r"(\w+)\(\)", expression.group(1))
    catalog = {}
    for name in names:
        m = re.search(r"(?:private |internal )?fun %s\(\)(?::Map<String,List<String>>)?\s*=\s*mapOf\(\s*\n" % name, app_text)
        if not m:
            raise SystemExit("AppText row function %s() not found" % name)
        for values in table_rows(app_text[m.end():]):
            catalog[values[0]] = values[1:]
    return catalog


def parse_tables(android):
    """SportsText.extra, SquashText.entries, VolleyText.labels/tips and CourtJourneyText.rows, each as
    ordered [key, es, ar, hi, nl] rows with Kotlin map semantics (first position, last value)."""
    def table(file, name):
        text = io.open(os.path.join(android, KOTLIN, "sports", file), encoding="utf-8").read()
        m = re.search(r"(?:private )?val %s=mapOf\(\s*\n" % name, text)
        if not m:
            raise SystemExit("%s.%s not found" % (file, name))
        rows = {}
        for values in table_rows(text[m.end():]):
            rows[values[0]] = values[1:]
        return [[k] + v for k, v in rows.items()]
    return {
        "extra": table("SportsText.kt", "extra"),
        "squash": table("SquashText.kt", "entries"),
        "volleyLabels": table("VolleyText.kt", "labels"),
        "volleyTips": table("VolleyText.kt", "tips"),
        "journey": table("CourtJourneyText.kt", "rows"),
    }


def swift_quote(s):
    return '"' + s.replace(BS, BS + BS).replace('"', BS + '"').replace("\n", BS + "n") + '"'


def facts_source(android):
    path = os.path.join(android, KOTLIN, "sports/core/Learning.kt")
    text = io.open(path, encoding="utf-8").read()

    def facts(name):
        start = text.index(" val %s=listOf(" % name)
        body = text[start:text.index("))\n", start) + 2]
        rows = []
        for line in body.split("\n"):
            if "Fact(" not in line:
                continue
            s = [v for _, v in kotlin_literals(line, normalise=False)]
            level = int(re.search(r'\),(\d),"', line).group(1))
            rows.append((s[0], s[1], s[2:6], s[6:10], level, s[10], s[11], s[12]))
        return rows

    def emit(rows):
        out = []
        for en, he, ce, ch, level, why_en, why_he, source in rows:
            out.append("        Fact(en: %s, he: %s,\n             choicesEn: [%s],\n             choicesHe: [%s],\n             level: %d, whyEn: %s, whyHe: %s, source: %s)," % (
                swift_quote(en), swift_quote(he), ", ".join(map(swift_quote, ce)), ", ".join(map(swift_quote, ch)), level,
                swift_quote(why_en), swift_quote(why_he), swift_quote(source)))
        out[-1] = out[-1].rstrip(",")
        return "\n".join(out)

    english, world = facts("english"), facts("world")
    if len(english) != 24 or len(world) != 12:
        raise SystemExit("unexpected bank sizes %d/%d" % (len(english), len(world)))
    return ("// Generated from Android sports core/Learning.kt (QuestionBank.english / QuestionBank.world) by\n"
            "// Scripts/audit-sports.py --write-facts. Do not edit by hand: the banks must match Android exactly.\n"
            "// Curated, local, unambiguous. The first option is the verified correct answer.\n\n"
            "extension QuestionBank {\n    static let english: [Fact] = [\n%s\n    ]\n\n    static let world: [Fact] = [\n%s\n    ]\n}\n"
            % (emit(english), emit(world)))


# ---------------------------------------------------------------- checks

def dump(path, value):
    with io.open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(value, f, ensure_ascii=False, indent=0)
        f.write("\n")


def check_catalog(android, write):
    catalog = parse_catalog(android)
    target = os.path.join(SPORTS, "Localization", "apptext.json")
    rows = [[k] + v for k, v in catalog.items()]
    if write:
        dump(target, rows)
    current = json.load(io.open(target, encoding="utf-8"))
    ok = current == rows
    print("catalog: %d rows, %s" % (len(rows), "identical" if ok else "DIFFERENT"))
    return ok


def check_tables(android, write):
    tables = parse_tables(android)
    target = os.path.join(SPORTS, "Localization", "sportstext.json")
    if write:
        dump(target, tables)
    current = json.load(io.open(target, encoding="utf-8"))
    ok = current == tables
    print("tables: %s, %s" % (", ".join("%s %d" % (k, len(v)) for k, v in tables.items()), "identical" if ok else "DIFFERENT"))
    return ok


def check_facts(android, write):
    target = os.path.join(SPORTS, "Core", "QuestionFacts.swift")
    expected = facts_source(android)
    if write:
        with io.open(target, "w", encoding="utf-8", newline="\n") as f:
            f.write(expected)
    ok = io.open(target, encoding="utf-8").read() == expected
    print("facts: %s" % ("identical" if ok else "DIFFERENT"))
    return ok


def check_texts(android):
    kotlin_dir = os.path.join(android, KOTLIN)
    android_pairs = set()
    android_singles = set()
    for folder, _, files in os.walk(kotlin_dir):
        for name in files:
            if name.endswith(".kt") and name != "AppText.kt":
                text = io.open(os.path.join(folder, name), encoding="utf-8").read()
                android_pairs |= call_pairs(text, kotlin_literals, ["tr", r"AppText\.t", r"SportsText\.t", "t"])
                # Settings rows passed to tr() later: Triple(key, English, Hebrew).
                for m in re.finditer(r'Triple\("[^"]*","([^"]*)","([^"]*)"\)', text):
                    android_pairs.add((m.group(1), m.group(2)))
                android_singles |= {v for _, v in kotlin_literals(text)}
    swift_pairs = set()
    for folder, _, files in os.walk(SPORTS):
        for name in files:
            if name.endswith(".swift"):
                text = io.open(os.path.join(folder, name), encoding="utf-8").read()
                swift_pairs |= call_pairs(text, swift_literals, ["tr", r"AppText\.t", r"SportsText\.t"])
    known = {en for en, _ in android_pairs}
    missing = []
    for en, he in sorted(swift_pairs, key=lambda p: p[0]):
        if he is not None and (en, he) in android_pairs:
            continue
        if he is None and (en in known or en in android_singles):
            continue
        if en in ("", "{}"):
            continue
        missing.append((en, he))
    for en, he in missing:
        print("  iOS text not found on Android: %r / %r" % (en, he))
    unused = sorted({p for p in android_pairs if p[1] is not None} - swift_pairs)
    print("texts: %d iOS pairs, %d not matched, %d Android pairs unused on iOS" % (len(swift_pairs), len(missing), len(unused)))
    for en, he in unused:
        print("  Android only: %r" % en)
    return not missing


def check_art(android):
    try:
        from PIL import Image
    except ImportError:
        print("art: skipped (Pillow missing)")
        return True
    art = os.path.join(SPORTS, "Assets.xcassets", "Art")
    ok = True
    count = 0
    expected = {n[:-5] for n in os.listdir(os.path.join(android, MODULE, "assets/art")) if n.endswith(".webp")}
    for entry in sorted(os.listdir(art)):
        if not entry.endswith(".imageset"):
            continue
        name = entry[:-len(".imageset")]
        png = os.path.join(art, entry, name + ".png")
        source = os.path.join(android, MODULE, "assets/art", name + ".webp")
        a, b = Image.open(png), Image.open(source)
        a.load()
        b.load()
        if b.mode not in ("RGB", "RGBA"):
            b = b.convert("RGBA")
        if a.size != b.size or a.mode != b.mode or a.tobytes() != b.tobytes():
            print("  pixel mismatch: " + name)
            ok = False
        expected.discard(name)
        count += 1
    for name in sorted(expected):
        print("  missing art: " + name)
        ok = False
    print("art: %d images %s" % (count, "lossless" if ok else "MISMATCH"))
    return ok


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def check_files(android):
    pairs = [("Audio/" + n + ".mp3", MODULE + "/res/raw/" + n + ".mp3") for n in SOUNDS]
    pairs += [("Art/" + n, MODULE + "/assets/art/" + n) for n in ("atlas.json", "directions.json", "volley-actions.json", "volley-passes.json")]
    pairs += [("Privacy/privacy-%s.html" % n, MODULE + "/assets/privacy/%s.html" % n) for n in LANGUAGES]
    pairs += [("Assets.xcassets/Menu/%s_menu_clean.imageset/%s_menu_clean.png" % (n, n), "%s/src/main/res/drawable-nodpi/%s_menu_clean.png" % (n, n))
              for n in ("squash", "volley")]
    ok = True
    for ios, droid in pairs:
        if sha(os.path.join(SPORTS, ios)) != sha(os.path.join(android, droid)):
            print("  differs: " + ios)
            ok = False
    print("files: %d %s" % (len(pairs), "identical" if ok else "DIFFERENT"))
    return ok


def check_swift():
    ok = True
    mains = 0
    total = 0
    for base in (SPORTS, TESTS):
        if not os.path.isdir(base):
            continue
        for folder, _, files in os.walk(base):
            for name in files:
                if not name.endswith(".swift"):
                    continue
                total += 1
                data = open(os.path.join(folder, name), "rb").read()
                if b"\r" in data:
                    print("  CRLF: " + name)
                    ok = False
                if base == SPORTS:
                    mains += len(re.findall(rb"^@main\b", data, re.M))
    if mains != 1:
        print("  @main count: %d" % mains)
        ok = False
    print("swift: %d files, %s" % (total, "ok" if ok else "PROBLEMS"))
    return ok


def print_hashes(android):
    used = ["README.md", "DECISIONS.md", "BUILD_STATUS.md", "ASSET_MANIFEST.md", "EXTERNAL_ACTIONS_REQUIRED.md",
            "firebase/database.rules.json", "sports/build.gradle.kts", "squash/build.gradle.kts", "volley/build.gradle.kts",
            "squash/src/main/AndroidManifest.xml", "volley/src/main/AndroidManifest.xml"]
    for folder in (MODULE + "/java", "sports/src/test/java", MODULE + "/assets", MODULE + "/res"):
        for base, _, files in os.walk(os.path.join(android, folder)):
            for name in files:
                used.append(os.path.relpath(os.path.join(base, name), android).replace(os.sep, "/"))
    for rel in sorted(set(used)):
        path = os.path.join(android, rel)
        if os.path.isfile(path):
            print("| `%s` | `%s` |" % (rel, sha(path)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--android", default=r"C:\Projects\MinikSports")
    parser.add_argument("--write-facts", action="store_true")
    parser.add_argument("--write-catalog", action="store_true")
    parser.add_argument("--hashes", action="store_true")
    args = parser.parse_args()
    if args.hashes:
        print_hashes(args.android)
        return 0
    results = [check_catalog(args.android, args.write_catalog), check_tables(args.android, args.write_catalog),
               check_facts(args.android, args.write_facts), check_texts(args.android), check_art(args.android),
               check_files(args.android), check_swift()]
    print("RESULT: " + ("PASS" if all(results) else "FAIL"))
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
