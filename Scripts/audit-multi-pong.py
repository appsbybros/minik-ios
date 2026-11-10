#!/usr/bin/env python3
"""Static audit of the Multi Ping Pong iOS port (target MinikMultiPingPong, sources in MultiPong/).

Checks, without building or touching the network:
  * the public entry points shared Sources/** rely on still exist (ModernPongView, ModernPongExperience, ModernPongResult);
  * the Firebase client writes only under minikCrossPong/ with the Android app name and bundle id;
  * ads stay off (no interstitial unit, no ad unit IDs) in MultiPong/;
  * the Firebase rules mirror keeps the root closed and matches the hash recorded in docs/multi-pong-ios-handoff.md;
  * every unit-test file imports the app module with @testable;
  * braces, brackets and parentheses balance in every Swift file of MultiPong/ and Tests/MultiPongTests/;
  * the text catalog (MultiPong/MPTextCatalog.swift, Android AppText) is complete: four non-blank columns per row, no
    duplicate keys, and every {n} of a translation exists in its English key;
  * MPText.resourceTexts (Android strings.xml texts that differ from the catalog row of their English text) names catalog
    keys and catalog languages, really differs from the catalog, and its texts are shown through MPText.resource, never t();
  * the six app languages agree in MPText.swift and in the CFBundleLocalizations of the MinikMultiPingPong target;
  * (5c1aa4d) the separate team-room root `minikCrossTeams` stays in the merged rules, the team protocol keeps its Android
    names, and the 5c1aa4d art and audio are in Resources/MultiPongAssets.xcassets.
  * (stage 1, 2026-11-09) Starter and the elimination final on the cross table against the Android sources at STAGE1_COMMIT
    (dd94c09, read with `git show` from --android or the MinikCrossPong checkout next to this repository): the control levels,
    their wire values, Starter's tolerances, stroke and tap depth, ControlChoice, the picker order, every Starter and final-duel
    text with Android's resource text in six languages, the catalog rows novemberSix2026 and the final-duel rules.
  * (stage 2, 2026-11-09) the court, camera and characters against the same STAGE1_COMMIT: the changed Minik art and atlas
    byte for byte, the court's tilt, margin, fit and grounded stances, the close camera, the far name badge, the table-rim body
    mask, the traced front hands of Minik, Mia, Flare and Kyra, the terrace foliage polygons, and the classic court's tabletop,
    far Minik, slim rim, landscape anchor and reception pivot.
  * (stage 3, 2026-11-09) playing against the same STAGE1_COMMIT: single-tap Starter/Standard returns and their separate aiming
    gesture (moveOnly / canAimReturn / aimReturn) on both courts, court-tap aiming (tappedAim, otherCourt), the drawn paddle's
    recovery (CrossPaddlePose), the learners' footwork reach and drag, the double tap's 40-substep hold and system timeout, the
    slower raised pass, the aiming lessons' wait, and the loose ball after a point (LooseBall, its far-end stop, the draw order,
    the checkpoint rules), rule by rule.
  * (stage 4, 2026-11-09) rooms against the same STAGE1_COMMIT: the Firebase rules mirror (merged and fragment) byte for byte
    with Android's (the friendly host's house-only final) and its multi21 rules tests, the "Loading…" and novemberSeven2026
    catalog rows, the Back question's texts, Play again, the rematch room, saved friendly and team lineups, clockwise seats,
    the full-roster pause, explicit saves, SaveComparison, the lobby rollback and two-player tournaments, rule by rule.
  * (stage 5, 2026-11-10) guidance and polish against the same STAGE1_COMMIT: the dailyGuide2026 and courtTap2026 catalog rows,
    tap_marked_court / tap_opponent_side_to_serve in six languages, CrossPracticeGuide, receivingSetTip, the court-tap help and
    tutorial texts, the Daily controls line and HUD, tutorial navigation, the result card's readable lettering, the steady point
    highlight, tournament tables, spacing (PongSpacing), status-line alignment, the team scoreboard padding and the larger button
    lettering, rule by rule; and the iOS-only translations of MPTextIOS (owner decision): never an Android catalog key, every
    language translated.
  * (2026-11-10, owner decision) the iOS-only fixes: a 2-seat friendly game never saves or restores a lineup, the host is not
    kept behind the Loading page while their own Ready is needed, the new MPTextIOS rows, and no MultiPong interface text that
    falls back to English in Spanish, Arabic, Hindi or Dutch (every English literal resolves to a row; no EN/HE-only call site).

With --android <path to the MinikCrossPong checkout>, it also (stage 5: every Android file read as committed at ANDROID_COMMIT
with `git show`, so a working tree ahead of it or checked out with CRLF line endings changes nothing)
  * re-hashes every Android file listed in the handoff document: the committed blobs of ANDROID_COMMIT, including the files
    listed in its "working-tree files" sections (the files the audit compares);
  * compares MultiPong/MPTextCatalog.swift row by row with the Android AppText.kt;
  * compares every string of values-es, -ar, -hi and -nl strings.xml (Android getString) with the text MPText shows for its
    English text: the catalog row, or MPText.resourceTexts where Android's resource text differs;
  * compares every string of values*/journey.xml (5c1aa4d) and values*/issue_review.xml with MPText.journeyTexts / issueTexts.

With --android and --write-catalog it regenerates MultiPong/MPTextCatalog.swift from the Android AppText.kt instead of
comparing (then run the audit again).

Usage: python3 Scripts/audit-multi-pong.py [--android C:/Projects/MinikCrossPong [--write-catalog]]
"""
import argparse
import hashlib
import html
import json
import pathlib
import re
import subprocess
import sys
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOC = ROOT / 'docs' / 'multi-pong-ios-handoff.md'
CATALOG = ROOT / 'MultiPong' / 'MPTextCatalog.swift'
# Stage 5 (2026-11-10): every app-side change of 47ad0c9..dd94c09 is on iOS, so the audit follows dd94c09 in full.
ANDROID_COMMIT = 'dd94c0946783360826e43014b20b1bd9c74549b3'
APP_TEXT = 'app/src/main/java/com/appsbybros/minik/localization/AppText.kt'
STRINGS = 'app/src/main/res/values{}/strings.xml'
JOURNEY = 'app/src/main/res/values{}/journey.xml'
# 7254ab2: the issue-report fixes' resource strings (MPText.issueTexts).
ISSUE = 'app/src/main/res/values{}/issue_review.xml'
# Android resource folders of the app languages (Hebrew is values-iw).
FOLDERS = {'he': '-iw', 'es': '-es', 'ar': '-ar', 'hi': '-hi', 'nl': '-nl'}
# Android strings that are not catalog rows: the app name, "Minik" and two format-only strings, the same in every language.
STRINGS_WITHOUT_ROW = {'app_name', 'minik', 'guide_progress', 'guide_live'}
LANGUAGES = ['en', 'he', 'ar', 'es', 'hi', 'nl']
COLUMNS = ['es', 'ar', 'hi', 'nl']
BACKSLASH = chr(92)
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def read(rel):
    return (ROOT / rel).read_text(encoding='utf-8')


def balanced(text):
    """Bracket balance outside strings and comments (Swift string interpolation aware)."""
    pairs = {')': '(', ']': '[', '}': '{'}
    stack, i, n = [], 0, len(text)
    in_string = multi = False
    interpolation = []
    while i < n:
        c = text[i]
        if multi:
            if text.startswith('"""', i):
                multi, i = False, i + 3
                continue
            i += 1
            continue
        if in_string:
            if c == BACKSLASH and i + 1 < n and text[i + 1] == '(':
                interpolation.append(len(stack))
                stack.append('(')
                in_string, i = False, i + 2
                continue
            if c == BACKSLASH:
                i += 2
                continue
            if c == '"':
                in_string = False
            i += 1
            continue
        if text.startswith('//', i):
            j = text.find('\n', i)
            i = n if j < 0 else j
            continue
        if text.startswith('/*', i):
            j = text.find('*/', i)
            i = n if j < 0 else j + 2
            continue
        if text.startswith('"""', i):
            multi, i = True, i + 3
            continue
        if c == '"':
            in_string, i = True, i + 1
            continue
        if c in '([{':
            stack.append(c)
        elif c in ')]}':
            if not stack or stack[-1] != pairs[c]:
                return False
            stack.pop()
            if c == ')' and interpolation and interpolation[-1] == len(stack):
                interpolation.pop()
                in_string = True
        i += 1
    return not stack and not in_string and not multi


def android_file(android, rel):
    """An Android file as committed at ANDROID_COMMIT (stage 5): the audit reads `git show`, so a working tree that is ahead of
    ANDROID_COMMIT, or one checked out with CRLF line endings, cannot change what it compares."""
    result = subprocess.run(['git', '-C', str(android), 'show', f'{ANDROID_COMMIT}:{rel}'], capture_output=True)
    if result.returncode != 0:
        raise OSError(f'{rel} is missing at {ANDROID_COMMIT[:7]}')
    return result.stdout


def android_text(android, rel):
    return android_file(android, rel).decode('utf-8')


def documented_hashes():
    """(committed blobs at ANDROID_COMMIT, working-tree files) listed under the document's SHA-256 headings."""
    committed, worktree = {}, {}
    target = committed
    for line in DOC.read_text(encoding='utf-8').splitlines():
        if line.startswith('#'):
            if 'SHA-256' in line:
                target = worktree if 'working-tree' in line else committed
            continue
        m = re.fullmatch(r'([0-9a-f]{64})  (\S.*)', line.strip())
        if m:
            target[m.group(2)] = m.group(1)
    return committed, worktree


# ---- text catalog (Android AppText.kt <-> MultiPong/MPTextCatalog.swift) ---------------------------------------------

def kotlin_string(s, i):
    """The Kotlin string literal at s[i] == '"' (no templates allowed) and the index after it."""
    i += 1
    out = []
    simple = {'n': '\n', 't': '\t', 'r': '\r', '"': '"', "'": "'", BACKSLASH: BACKSLASH, '$': '$', 'b': '\b'}
    while True:
        c = s[i]
        if c == '"':
            return ''.join(out), i + 1
        if c == BACKSLASH:
            e = s[i + 1]
            if e in simple:
                out.append(simple[e])
                i += 2
            elif e == 'u':
                out.append(chr(int(s[i + 2:i + 6], 16)))
                i += 6
            else:
                raise ValueError(f'unknown Kotlin escape \\{e}')
            continue
        if c == '$' and (s[i + 1].isalpha() or s[i + 1] in '_{'):
            raise ValueError('a Kotlin string template in AppText: ' + s[i - 20:i + 20])
        out.append(c)
        i += 1


def android_rows(text):
    """[(chunk, key, [es, ar, hi, nl])] in AppText order: the row groups in the order `rows` adds them (5c1aa4d puts
    receptionAssistance2026 first and journey2026 last; a later group's value wins for a repeated key, as in Kotlin).
    Kotlin's `Map + Map` keeps a repeated key at its first position with the later value (47ad0c9 repeats one template key in
    issueV8Review2026), so the rows are merged the same way and the catalog has every key once."""
    rows = []
    groups = {}
    for m in re.finditer(r'private fun (\w+)\(\)(?::Map<String,List<String>>)?\s*=\s*mapOf\(', text):
        groups[m.group(1)] = m.end()
    order = re.search(r'private val rows:Map<String,List<String>> by lazy \{([^}]*)\}', text)
    names = re.findall(r'(\w+)\(\)', order.group(1)) if order else sorted(groups, key=lambda n: groups[n])
    for name in names:
        if name not in groups:
            raise ValueError('AppText rows name an unknown group: ' + name)
        i = groups[name]
        while True:
            while text[i] in ' \r\n\t,':
                i += 1
            if text[i] == ')':
                break
            key, i = kotlin_string(text, i)
            to = re.compile(r'\s*to\s*listOf\(').match(text, i)
            if not to:
                raise ValueError('unexpected AppText row near ' + text[i:i + 60])
            i = to.end()
            values = []
            while True:
                while text[i] in ' \r\n\t,':
                    i += 1
                if text[i] == ')':
                    i += 1
                    break
                value, i = kotlin_string(text, i)
                values.append(value)
            rows.append((name, key, values))
    merged, seen = [], {}
    for name, key, values in rows:
        if key in seen:
            merged[seen[key]] = (merged[seen[key]][0], key, values)
        else:
            seen[key] = len(merged)
            merged.append((name, key, values))
    return merged


def swift_literal(value):
    out = ['"']
    for c in value:
        code = ord(c)
        if c == BACKSLASH:
            out.append(BACKSLASH * 2)
        elif c == '"':
            out.append(BACKSLASH + '"')
        elif c == '\n':
            out.append(BACKSLASH + 'n')
        elif c == '\r':
            out.append(BACKSLASH + 'r')
        elif c == '\t':
            out.append(BACKSLASH + 't')
        elif 0xD800 <= code <= 0xDFFF:
            raise ValueError('a lone surrogate in AppText')
        elif unicodedata.category(c) in ('Cc', 'Cf', 'Zl', 'Zp'):
            out.append(BACKSLASH + 'u{%X}' % code)
        else:
            out.append(c)
    out.append('"')
    return ''.join(out)


def parse_swift_string(s, i):
    """A literal written by swift_literal at s[i] == '"' and the index after it."""
    i += 1
    out = []
    simple = {'n': '\n', 'r': '\r', 't': '\t', '"': '"', BACKSLASH: BACKSLASH, '0': '\0', "'": "'"}
    while True:
        c = s[i]
        if c == '"':
            return ''.join(out), i + 1
        if c == '\n':
            raise ValueError('a line break inside a catalog literal')
        if c == BACKSLASH:
            e = s[i + 1]
            if e in simple:
                out.append(simple[e])
                i += 2
            elif e == 'u' and s[i + 2] == '{':
                j = s.index('}', i)
                out.append(chr(int(s[i + 3:j], 16)))
                i = j + 1
            else:
                raise ValueError(f'unexpected Swift escape \\{e} in the catalog')
            continue
        out.append(c)
        i += 1


def swift_rows(text):
    """[(chunk, key, [values])] from MPTextCatalog.swift."""
    rows = []
    chunk = None
    for line in text.splitlines():
        m = re.match(r'\s*private static let (\w+): \[\(String, \[String\]\)\] = \[\s*$', line)
        if m:
            chunk = m.group(1)
            continue
        stripped = line.strip()
        if not stripped.startswith('("'):
            continue
        key, i = parse_swift_string(stripped, 1)
        if not stripped.startswith(', [', i):
            raise ValueError('unexpected catalog row: ' + stripped[:80])
        i += 3
        values = []
        while True:
            value, i = parse_swift_string(stripped, i)
            values.append(value)
            if stripped.startswith(', ', i):
                i += 2
                continue
            break
        if stripped[i:] not in ('])', ']),'):
            raise ValueError('unexpected catalog row end: ' + stripped[-40:])
        rows.append((chunk, key, values))
    return rows


def write_catalog(rows, source_hash):
    chunks = []
    for chunk, _, _ in rows:
        if chunk not in chunks:
            chunks.append(chunk)
    lines = [
        '// Generated by Scripts/audit-multi-pong.py --write-catalog from the Android catalog',
        f'// {APP_TEXT}',
        f'// (MinikCrossPong {ANDROID_COMMIT[:7]}, SHA-256 {source_hash}).',
        '// Do not edit by hand: regenerate it from the Android file.',
        '',
        '/// Android `AppText` rows in their Android order: the English key, then its Spanish, Arabic, Hindi and Dutch texts',
        '/// (`MPText.columns`). `{0}`, `{1}`… stand for the names and numbers inside a text. Read through `MPText`.',
        'enum MPTextCatalog {',
        '    static let rows: [(String, [String])] = Array([',
        '        ' + ', '.join(chunks),
        '    ].joined())',
    ]
    for chunk in chunks:
        lines.append(f'    private static let {chunk}: [(String, [String])] = [')
        body = [r for r in rows if r[0] == chunk]
        for index, (_, key, values) in enumerate(body):
            comma = ',' if index < len(body) - 1 else ''
            lines.append('        (' + swift_literal(key) + ', [' + ', '.join(swift_literal(v) for v in values) + '])' + comma)
        lines.append('    ]')
    lines.append('}')
    CATALOG.write_bytes(('\n'.join(lines) + '\n').encode('utf-8'))


def placeholders(value):
    return set(int(n) for n in re.findall(r'\{([0-9]+)\}', value))


def check_catalog(rows):
    keys = [key for _, key, _ in rows]
    check(len(rows) > 0, 'MPTextCatalog.swift has no rows')
    check(len(keys) == len(set(keys)), 'MPTextCatalog.swift has duplicate keys')
    for _, key, values in rows:
        check(len(values) == len(COLUMNS), f'catalog row without {len(COLUMNS)} columns: {key[:60]!r}')
        for column, value in zip(COLUMNS, values):
            check(value.strip() != '', f'blank {column} text for {key[:60]!r}')
            check(placeholders(value) <= placeholders(key), f'{column} text uses a placeholder its key lacks: {key[:60]!r}')


# ---- Android strings.xml (getString) <-> MPText.resourceTexts ---------------------------------------------------------

def literal_at(row, i):
    """The Swift string literal that must start at row[i] and the index after it."""
    if not row.startswith('"', i):
        raise ValueError('a string literal was expected: ' + row[:80])
    return parse_swift_string(row, i)


def resource_overrides(text):
    """MPText.resourceTexts of MPText.swift: {(English text, language): Android resource text}."""
    if re.search(r'static let resourceTexts: \[String: \[String: String\]\] = \[:\]', text):
        return {}
    block = re.search(r'static let resourceTexts: \[String: \[String: String\]\] = \[\n(.*?)\n    \]\n', text, re.S)
    if not block:
        raise ValueError('MPText.resourceTexts is missing')
    overrides = {}
    for line in block.group(1).splitlines():
        row = line.strip()
        if not row or row.startswith('//'):
            continue
        key, i = literal_at(row, 0)
        if not row.startswith(': [', i):
            raise ValueError('unexpected MPText.resourceTexts row: ' + row[:80])
        i += 3
        while True:
            lang, i = literal_at(row, i)
            if not row.startswith(': ', i):
                raise ValueError('unexpected MPText.resourceTexts row: ' + row[:80])
            value, i = literal_at(row, i + 2)
            overrides[(key, lang)] = value
            if not row.startswith(', ', i):
                break
            i += 2
        if row[i:] not in (']', '],'):
            raise ValueError('unexpected MPText.resourceTexts row end: ' + row[-40:])
    return overrides


def check_overrides(overrides, table, sources):
    """Every MPText.resourceTexts entry is a real difference of a catalog row, shown through MPText.resource only."""
    for (key, lang), value in sorted(overrides.items()):
        check(key in table, f'MPText.resourceTexts: {key[:60]!r} is not a catalog key')
        check(lang in COLUMNS, f'MPText.resourceTexts: {lang!r} is not a catalog language')
        check(value.strip() != '', f'MPText.resourceTexts: blank {lang} text for {key[:60]!r}')
        if key in table and lang in COLUMNS:
            check(value != table[key][COLUMNS.index(lang)], f'MPText.resourceTexts repeats the catalog {lang} text of {key[:60]!r}')
    for key in sorted({key for key, _ in overrides}):
        literal = swift_literal(key)
        check(f'MPText.resource({literal},' in sources, f'{key[:60]!r} is not shown through MPText.resource')
        check(f't({literal},' not in sources, f'{key[:60]!r} is also shown through t(), without its resource text')


def android_strings(text):
    """{name: text} of an Android strings.xml: XML entities and backslash escapes decoded, unescaped double quotes dropped."""
    found = {}
    for m in re.finditer(r'<string name="([^"]+)"[^>]*>(.*?)</string>', text, re.S):
        raw = html.unescape(m.group(2))
        out, i = [], 0
        while i < len(raw):
            c = raw[i]
            if c == BACKSLASH and i + 1 < len(raw):
                e = raw[i + 1]
                if e == 'u':
                    out.append(chr(int(raw[i + 2:i + 6], 16)))
                    i += 6
                    continue
                out.append({'n': '\n', 't': '\t'}.get(e, e))
                i += 2
                continue
            if c != '"':
                out.append(c)
            i += 1
        found[m.group(1)] = ''.join(out)
    return found


def check_resources(android, table, overrides):
    """Android's translated strings.xml (shown with getString) against what MPText shows for the same English text: the
    catalog row, or MPText.resourceTexts where the two differ. Returns the number of strings compared."""
    english = android_strings(android_text(android, STRINGS.format('')))
    used, compared = set(), 0
    for column, lang in enumerate(COLUMNS):
        local = android_strings(android_text(android, STRINGS.format('-' + lang)))
        check(sorted(local) == sorted(english), f'values-{lang}/strings.xml and values/strings.xml name different strings')
        for name, value in sorted(local.items()):
            key = english.get(name)
            if key not in table:
                check(name in STRINGS_WITHOUT_ROW and value == key, f'values-{lang} string {name} is not a catalog row')
                continue
            expected = table[key][column]
            if (key, lang) in overrides:
                used.add((key, lang))
                expected = overrides[(key, lang)]
            check(value == expected, f'values-{lang} {name}: Android shows {value!r}, MPText {expected!r}')
            compared += 1
    check(used == set(overrides), 'MPText.resourceTexts has a text that no Android strings.xml has')
    return compared


def journey_texts(text, name='journeyTexts'):
    """MPText.journeyTexts (or MPText.issueTexts) of MPText.swift: {(English text, language): text}."""
    block = re.search(r'static let ' + name + r': \[String: \[String: String\]\] = \[\n(.*?)\n    \]\n', text, re.S)
    if not block:
        raise ValueError(f'MPText.{name} is missing')
    texts = {}
    for line in block.group(1).splitlines():
        row = line.strip()
        if not row or row.startswith('//'):
            continue
        key, i = literal_at(row, 0)
        if not row.startswith(': [', i):
            raise ValueError('unexpected MPText.journeyTexts row: ' + row[:80])
        i += 3
        while True:
            lang, i = literal_at(row, i)
            value, i = literal_at(row, i + 2)
            texts[(key, lang)] = value
            if not row.startswith(', ', i):
                break
            i += 2
    return texts


def check_journey(android, texts, files=None, name='journeyTexts'):
    """Android values*/journey.xml (or issue_review.xml) against MPText.journeyTexts (issueTexts). Returns the number compared."""
    files = files or JOURNEY
    english = android_strings(android_text(android, files.format('')))
    compared = 0
    for string, key in sorted(english.items()):
        for lang, folder in FOLDERS.items():
            local = android_strings(android_text(android, files.format(folder)))
            check(texts.get((key, lang)) == local.get(string), f'{files.format(folder)} {string} ({lang}): Android shows {local.get(string)!r}, MPText {texts.get((key, lang))!r}')
            compared += 1
    check(len(texts) == compared, f'MPText.{name} has a text that no Android {files} has')
    return compared


# ---- Stage 1 (2026-11-09): Starter and the final duel, checked against Android STAGE1_COMMIT -----------------------------
# ANDROID_COMMIT stays at the last fully matched commit until every stage of the dd94c09 port is done; these checks read the
# Android sources of the stage-1 behaviour at STAGE1_COMMIT with `git show`, so uncommitted Android work cannot change them.

STAGE1_COMMIT = 'dd94c0946783360826e43014b20b1bd9c74549b3'
KT = 'app/src/main/java/com/appsbybros/minik/pingpong/'
# Android Difficulty -> iOS MPLevel (the same ordinals).
DIFFICULTY_LEVEL = {'STARTER': 'easy', 'EASY': 'medium', 'MEDIUM': 'hard', 'HARD': 'superHard', 'BEGINNER': 'beginner'}


def android_blob(android, rel):
    result = subprocess.run(['git', '-C', str(android), 'show', f'{STAGE1_COMMIT}:{rel}'], capture_output=True)
    if result.returncode != 0:
        raise OSError(f'{rel} is missing at {STAGE1_COMMIT[:7]}')
    return result.stdout.decode('utf-8')


def kotlin_pairs(text, starter=r'\btr\(', two=True):
    """Every `tr("en", "he")` (or AppText.t("en","he",…)) of a Kotlin source as decoded (en, he) pairs."""
    pairs = []
    for m in re.finditer(starter, text):
        i = m.end()
        while text[i] in ' \t':
            i += 1
        if text[i] != '"':
            continue
        try:
            en, i = kotlin_string(text, i)
            if not two:
                pairs.append((en, None))
                continue
            while text[i] in ' \t,\r\n':
                i += 1
            if text[i] != '"':
                continue
            he, _ = kotlin_string(text, i)
        except ValueError:
            continue  # a text with a Kotlin template is not one of the compared texts
        pairs.append((en, he))
    return pairs


def number(value):
    return float(value if not value.startswith('.') else '0' + value)


def swift_pair(en, he):
    return swift_literal(en) + ', ' + swift_literal(he)


def has_pair(sources, en, he):
    """A Swift call site with the English and Hebrew text next to each other (a line break may separate them)."""
    return re.search(re.escape(swift_literal(en)) + r',\s*' + re.escape(swift_literal(he)), sources) is not None


def check_stage1(android, sources):
    """Starter (b0cdeb3) and the elimination final on the cross table (1fc4bc2, b0cdeb3, 452d82c) against Android."""
    engine = android_blob(android, KT + 'cross/CrossEngine.kt')
    ios_engine = read('MultiPong/CrossEngine.swift')
    # The control levels in Kotlin `entries` order, their wire values and their Difficulty.
    enum = re.search(r'enum class CrossControl\(val choice: Int, val difficulty: Difficulty\) \{\s*(.*?);', engine, re.S)
    levels = re.findall(r'(\w+)\((\d+), Difficulty\.(\w+)\)', enum.group(1)) if enum else []
    check([name for name, _, _ in levels] == ['BEGINNER', 'STANDARD', 'PRO', 'STARTER'], f'Android CrossControl entries changed: {levels}')
    cases = re.search(r'enum CrossControl: CaseIterable \{\s*case ([a-z, ]+)\r?\n', ios_engine)
    check(cases and [c.strip() for c in cases.group(1).split(',')] == [n.lower() for n, _, _ in levels],
          'CrossControl cases differ from the Android entries order')
    for name, choice, difficulty in levels:
        case = name.lower()
        check(f'case .{case}: return {choice}\r\n' in ios_engine or f'case .{case}: return {choice}\n' in ios_engine,
              f'CrossControl.{case}.choice is not {choice}')
        check(f'case .{case}: return .{DIFFICULTY_LEVEL[difficulty]}' in ios_engine, f'CrossControl.{case}.level is not Difficulty.{difficulty}')
    # Starter's input forgiveness and stroke.
    tuning = re.search(r'if\(control==CrossControl\.STARTER\)it\.copy\(tapSpatialTolerance=([.\d]+),tapTimingWindow=([.\d]+)\)', engine)
    ios_tuning = re.search(r'if control == \.starter \{ own\.tapSpatialTolerance = ([.\d]+); own\.tapTimingWindow = ([.\d]+) \}', ios_engine)
    check(tuning and ios_tuning and [number(v) for v in tuning.groups()] == [number(v) for v in ios_tuning.groups()],
          'Starter tap tolerance/timing differ from Android')
    stroke = re.search(r'fun localStroke\(control: CrossControl\) = when\(control\)\{CrossControl\.PRO->Stroke\(\);'
                       r'CrossControl\.STARTER->Stroke\(([.\d]+),([.\d]+),([.\d]+),([.\d]+)\);else->Stroke\(([.\d]+),([.\d]+),([.\d]+),([.\d]+)\)\}', engine)
    ios_starter = re.search(r'case \.starter: return MPStroke\(contactAt: ([.\d]+), windowEnd: ([.\d]+), followEnd: ([.\d]+), total: ([.\d]+)\)', ios_engine)
    ios_other = re.search(r'case \.beginner, \.standard: return MPStroke\(contactAt: ([.\d]+), windowEnd: ([.\d]+), followEnd: ([.\d]+), total: ([.\d]+)\)', ios_engine)
    check(stroke and ios_starter and ios_other and [number(v) for v in stroke.groups()] ==
          [number(v) for v in ios_starter.groups() + ios_other.groups()], 'the local strokes differ from Android localStroke')
    depth = re.search(r'geometry\.toLocal\(local,ball\.position\)\.v >= if\(control==CrossControl\.STARTER\)([.\d]+) else ([.\d]+)\)\)\) point else null', engine)
    ios_depth = re.search(r'let depth = control == \.starter \? ([.\d]+) : ([.\d]+)\r?\n', ios_engine)
    check(depth and ios_depth and [number(v) for v in depth.groups()] == [number(v) for v in ios_depth.groups()],
          'the travelling-ball depth of a Starter/Standard tap differs from Android')
    for kotlin, swift in [('CrossControl.STANDARD, CrossControl.STARTER -> if (point != null && geometry.inStrikeZone(local, point)) {',
                           'case .standard, .starter:'),
                          ('else if(velocity.length>.08 && predictedReceiver==local)tap(local,point)',
                           'else if velocity.length > 0.08 && predictedReceiver == local { tap(local, point) }'),
                          ('if(pendingTap!=null)begin(local, point, ball.height, geometry.toLocal(local, point).u < 0)',
                           'if pendingTap != nil { begin(local, point, ball.height, left: geometry.toLocal(local, point).u < 0) }'),
                          ('if (pendingTap != null && s.age >= s.total && !s.contacted) { pendingTap = null; tappedAim=null }',
                           'if pendingTap != nil && s.age >= s.total && !s.contacted { pendingTap = nil; tappedAim = nil }'),
                          ('if (s.contacted || s.age<.04 || s.age>s.total) return', 'guard let tap = pendingTap, !s.contacted, s.age >= 0.04, s.age <= s.total else { return }'),
                          ('if (abs(geometry.toLocal(local,tap).u-geometry.toLocal(local,at).u) <= physics.tapSpatialTolerance && abs(timing) <= physics.tapTimingWindow)',
                           'if abs(geometry.toLocal(local, tap).u - geometry.toLocal(local, at).u) <= physics.tapSpatialTolerance && abs(timing) <= physics.tapTimingWindow {')]:
        check(kotlin in engine, f'Android CrossEngine changed: {kotlin[:70]}')
        check(swift in ios_engine, f'CrossEngine.swift lacks the Android rule: {swift[:70]}')
    # ControlChoice: the normalisation, the picker order and the titles.
    choice = android_blob(android, KT + 'multiplayer/ControlChoice.kt')
    check('fun normalize(value:Int)=when(value){0,2->0;1->1;3->3;else->4}' in choice, 'Android ControlChoice.normalize changed')
    physics = read('MultiPong/MPPhysics.swift')
    check(re.search(r'case 0, 2: return \.easy\s+case 1: return \.medium\s+case 3: return \.superHard\s+default: return \.beginner', physics),
          'MPLevel.control differs from Android ControlChoice.normalize')
    titles = {n: (en, he) for n, en, he in re.findall(r'(\d)->AppText\.t\("([^"]+)","([^"]+)",hebrew\)', choice)}
    knockout = read('MultiPong/MPKnockout.swift')
    level_of = {'1': 'medium', '0': 'easy', '3': 'superHard'}
    check(sorted(titles) == ['0', '1', '3'], f'Android ControlChoice.title changed: {titles}')
    for n, (en, he) in titles.items():
        check(f'case .{level_of[n]}: return MPText.t({swift_pair(en, he)}, he)' in knockout, f'MPControlChoice.title({n}) differs from Android')
    beginner = re.search(r'else->AppText\.t\("([^"]+)","([^"]+)",hebrew\)', choice)
    check(beginner and f'default: return MPText.t({swift_pair(*beginner.groups())}, he)' in knockout, 'MPControlChoice.title(Beginner) differs from Android')
    values = re.search(r'static let values = \[([\d, ]+)\]', knockout)
    for rel in (KT + 'multiplayer/PlayActivity.kt', KT + 'cross/CrossActivity.kt'):
        source = android_blob(android, rel)
        found = re.search(r'val controlValues ?= ?listOf\(([\d, ]+)\)', source)
        check(found and values and [int(v) for v in found.group(1).split(',')] == [int(v) for v in values.group(1).split(',')],
              f'MPControlChoice.values differs from {rel.rsplit("/", 1)[-1]} controlValues')
    check('ForEach(MPControlChoice.values' in read('MultiPong/ModernPongView.swift') and 'ForEach(MPControlChoice.values' in read('MultiPong/ModernPongRooms.swift'),
          'a control picker does not list MPControlChoice.values')
    # The Starter texts (EN/HE at the call sites) and Android's resource text in all six languages.
    starter_texts = set()
    for rel in ('cross/CrossText.kt', 'cross/CrossTutorial.kt', 'cross/CrossActivity.kt'):
        source = android_blob(android, KT + rel)
        for line in source.splitlines():
            if 'CrossControl.STARTER ->' in line:
                starter_texts.update(p for p in kotlin_pairs(line, r'\b(?:tr|AppText\.t)\('))
        if rel.endswith('CrossActivity.kt'):
            starter_texts.update(p for p in kotlin_pairs(source) if p[0].startswith('Starter gives you more time'))
    check(len(starter_texts) == 3, f'Android Starter texts changed: {sorted(starter_texts)}')
    for en, he in sorted(starter_texts):
        check(has_pair(sources, en, he), f'MultiPong lacks the Android Starter text {en[:50]!r}')
    issue = journey_texts(read('MultiPong/MPText.swift'), 'issueTexts')
    english = android_strings(android_blob(android, ISSUE.format(''))).get('control_starter_only')
    check(english is not None and f'MPText.issue({swift_literal(english)})' in sources, 'the Starter help (control_starter_only) is not shown')
    for lang, folder in FOLDERS.items():
        local = android_strings(android_blob(android, ISSUE.format(folder))).get('control_starter_only')
        check(local is not None and issue.get((english, lang)) == local, f'control_starter_only ({lang}): Android {local!r}, MPText {issue.get((english, lang))!r}')
    # The final duel: Android's texts at the iOS call sites, the catalog rows they use and the rules.
    play = android_blob(android, KT + 'multiplayer/PlayActivity.kt')
    match_activity = android_blob(android, KT + 'multiplayer/PrivateMatchActivity.kt')
    wanted = {'Finalists: ': play, 'Watch final duel': play, 'Watching the final duel. ': match_activity}
    for en, source in wanted.items():
        pair = sorted({p for p in kotlin_pairs(source) if p[0] == en})
        check(len(pair) == 1 and has_pair(sources, *pair[0]), f'MultiPong lacks the Android text {en!r}')
    expected_rows = [r for r in android_rows(android_blob(android, APP_TEXT)) if r[0] == 'novemberSix2026']
    catalog = [r for r in swift_rows(CATALOG.read_text(encoding='utf-8')) if r[0] == 'novemberSix2026']
    check(len(expected_rows) == 3 and catalog == expected_rows, 'the catalog rows novemberSix2026 differ from the Android AppText.kt')
    rules = [
        (KT + 'multiplayer/CrossFixture.kt', 'm.players.size == 2 -> CrossGoal.WIN', 'MultiPong/MPGroupMatch.swift', 'if m.players.count == 2 { return .win }'),
        (KT + 'multiplayer/CrossFixture.kt', 'fun usesCross(m: MatchRecord) = m.players.size >= 3 || PongRules.isDuel(m)', 'MultiPong/MPGroupMatch.swift',
         'static func usesCross(_ m: MPFixture) -> Bool { m.players.count >= 3 || MPRules.isDuel(m) }'),
        (KT + 'multiplayer/PongModels.kt', 'if(houseOnly(s,duel)&&s.kind!=SessionKind.FRIENDLY)simulated(s,duel) else duel', 'MultiPong/MPMultiplayerModels.swift',
         'houseOnly(s, duel) && s.kind != .friendly ? simulated(s, duel) : duel'),
        (KT + 'multiplayer/PongModels.kt', 'fun spectatedDuel(s:Session,m:MatchRecord,uid:String)=s.kind==SessionKind.FRIENDLY&&s.host==uid&&isDuel(m)&&houseOnly(s,m)&&s.humanMember(uid)',
         'MultiPong/MPMultiplayerModels.swift', 's.kind == .friendly && s.host == uid && isDuel(m) && houseOnly(s, m) && s.human(uid)'),
        (KT + 'multiplayer/PongModels.kt', 'return s.copy(matches=s.matches+(id to m.copy(phase=MatchPhase.PLAYING,starts=1)))', 'MultiPong/MPMultiplayerModels.swift',
         'm.phase = .playing; m.starts = 1'),
        (KT + 'cross/CrossMatch.kt', 'classicWinByTwo=seats.size==2 && control.difficulty.needsTwoPointLead && goal!=CrossGoal.TIEBREAK', 'MultiPong/CrossMatch.swift',
         'classicWinByTwo: seats.count == 2 && control.level.needsTwoPointLead && goal != .tiebreak'),
        (KT + 'cross/CrossMatch.kt', '(s.finished && goal==CrossGoal.TOP_TWO && it in s.placement.drop(2) && s.placement.take(2).none { f->f in s.eliminated })',
         'MultiPong/CrossMatch.swift', 's.finished && goal == .topTwo && s.placement.dropFirst(2).contains(seat) && !s.placement.prefix(2).contains(where: { s.eliminated.contains($0) })'),
        (KT + 'cross/CrossMatch.kt', '(s.next == null || (s.transition != null && s.next.active == s.active.filter { it !in s.eliminated }', 'MultiPong/CrossMatch.swift',
         'guard s.transition != nil, n.active == s.active.filter({ !s.eliminated.contains($0) })'),
        (KT + 'cross/CrossReferee.kt', '(!winByTwo || score[gain]-score[(gain+1)%players]>=2)', 'MultiPong/CrossReferee.swift',
         '(!winByTwo || board[gain] - board[crossMod(gain + 1, players)] >= 2)'),
        (KT + 'cross/CrossReferee.kt', 's.scores.all { it>=0 && (winByTwo || it<=target) }', 'MultiPong/CrossReferee.swift',
         's.scores.allSatisfy({ $0 >= 0 && (winByTwo || $0 <= target) })'),
        (KT + 'cross/CrossLink.kt', 'if(w.number("protocol",1)==1L && record.players.size==2 && PongRules.isDuel(record)){', 'MultiPong/CrossLink.swift',
         'if CrossWire.number(w, "protocol", 1) == 1 && record.players.count == 2 && MPRules.isDuel(record) {'),
        (KT + 'cross/CrossLink.kt', 'rallyId=score.rallies+1,ralliesPlayed=score.rallies,winner=winner,', 'MultiPong/CrossLink.swift',
         'state.engine.referee.rallyId = score.rallies + 1'),
        (KT + 'multiplayer/PrivateMatchActivity.kt', 'repository.mutate(s.kind,s.code,{PongRules.ready(it,duel.id,repository.uid,true)})', 'MultiPong/MPController.swift',
         '_ = try await self.repo.mutate(kind, code) { try MPRules.ready($0, match: id, uid: uid, value: true) }'),
        (KT + 'multiplayer/PlayActivity.kt', 's.matches.values.filter {(it.contains(repo.uid)||PongRules.spectatedDuel(s,it,repo.uid))&&it.phase==MatchPhase.PLAYING}.forEach {opened.add(it.id)}',
         'MultiPong/MPController.swift', 'for m in s.matches.values where (m.contains(uid) || MPRules.spectatedDuel(s, m, uid: uid)) && m.phase == .playing { opened.insert(m.id) }'),
        (KT + 'cross/CrossCourt.kt', 'private fun drawLocalAvatar(canvas:Canvas) { drawPlayer(canvas,viewSeat) }', 'MultiPong/CrossScene.swift', 'renderPlayer(viewSeat, depth: 3)'),
    ]
    for rel, kotlin, swift_file, swift in rules:
        check(kotlin in android_blob(android, rel), f'Android {rel.rsplit("/", 1)[-1]} changed: {kotlin[:60]}')
        check(swift in read(swift_file), f'{swift_file} lacks the Android rule: {swift[:60]}')
    return len(rules) + len(levels) + len(starter_texts)


# ---- Stage 2 (2026-11-09): the court, camera and characters, checked against Android STAGE1_COMMIT ----------------------------
# The same pinned commit (dd94c09) as stage 1: the art files must be Android's bytes, and the drawing numbers, masks and polygons
# must be Android's.

STAGE2_ART = [
    ('app/src/main/assets/pong-poses/minik.png', 'Resources/MultiPongAssets.xcassets/mpx_pose_minik.imageset/mpx_pose_minik.png'),
    ('app/src/main/assets/pong-poses/minik-walk.png', 'Resources/MultiPongAssets.xcassets/mpx_pose_minik_walk.imageset/mpx_pose_minik_walk.png'),
    ('app/src/main/assets/pong-poses/atlas.json', 'Resources/MultiPongAssets.xcassets/mpx_pose_atlas.dataset/atlas.json'),
]


def android_bytes(android, rel):
    result = subprocess.run(['git', '-C', str(android), 'show', f'{STAGE1_COMMIT}:{rel}'], capture_output=True)
    if result.returncode != 0:
        raise OSError(f'{rel} is missing at {STAGE1_COMMIT[:7]}')
    return result.stdout


def kotlin_polygons(block):
    """Every floatArrayOf(...) of a Kotlin block as a list of numbers."""
    return [[number(v.strip().rstrip('f')) for v in arrays.split(',')] for arrays in re.findall(r'floatArrayOf\(([^)]*)\)', block)]


def swift_number_lists(block):
    """Every innermost [n, n, ...] of a Swift literal as a list of numbers."""
    return [[number(v.strip()) for v in inner.split(',')] for inner in re.findall(r'\[([-\d., ]+)\]', block)]


def check_stage2(android, sources):
    """Court size and camera, character art and occlusion, table depth and the foreground foliage (Android 257e058 … fcfd6b2)."""
    compared = 0
    # Art: byte for byte.
    for rel, ios in STAGE2_ART:
        check(android_bytes(android, rel) == (ROOT / ios).read_bytes(), f'{ios} differs from Android {rel} at {STAGE1_COMMIT[:7]}')
        compared += 1
    court = android_blob(android, KT + 'cross/CrossCourt.kt')
    atlas = android_blob(android, KT + 'PongPlayerAtlas.kt')
    modern = android_blob(android, KT + 'ModernCourt.kt')
    scene_layout = android_blob(android, KT + 'MatchSceneLayout.kt')
    scene = read('MultiPong/CrossScene.swift')
    classic = read('MultiPong/MPScene.swift')
    # The traced front hands: the same polygons, per character and phase.
    for name in ['minik', 'mia', 'flare', 'kyra']:
        kotlin = re.search(r'private val ' + name + r'FrontHands by lazy \{(.*?)\n \}\n', atlas, re.S)
        swift = re.search(r'private static let ' + name + r'FrontHands: \[\[\[Double\]\]\] = \[(.*?)\n    \]', scene, re.S)
        check(kotlin and swift, f'{name} front hands are missing')
        if kotlin and swift:
            phases = re.split(r'\bmask\(', kotlin.group(1)[kotlin.group(1).index('listOf('):])[1:]
            expected = [kotlin_polygons(p) for p in phases]
            actual = [swift_number_lists(p) for p in re.split(r'(?<=\]\]),\n', swift.group(1))]
            check(len(expected) == 4 and expected == actual, f'{name} front hands differ from Android')
            compared += 1
        check(f'fun draw{name.capitalize()}FrontHands' in atlas, f'Android lacks draw{name.capitalize()}FrontHands')
    # The foreground foliage polygons, portrait then landscape.
    fg = re.search(r'if\(width<=height\)\{(.*?)\}else\{(.*?)\}\n', scene_layout, re.S)
    for label, block in (('portrait', fg.group(1) if fg else ''), ('landscape', fg.group(2) if fg else '')):
        expected = [[number(v) for pair in re.findall(r'([.\d]+)f to ([.\d]+)f', poly) for v in pair] for poly in re.findall(r'polygon\(listOf\((.*?)\)\)', block)]
        swift = re.search(r'private static let ' + label + r': \[\[Double\]\] = \[(.*?)\n    \]', scene, re.S)
        check(expected and swift and expected == swift_number_lists(swift.group(1)), f'the {label} foliage differs from Android')
        compared += 1
    # The classic tabletop path (arena pixels).
    top = re.search(r'tabletop\.reset\(\)\n(.*?)tabletop\.transform', modern, re.S)
    moves = re.search(r'let outline = CGMutablePath\(\)\n(.*?)let authored', classic, re.S)
    if top and moves:
        # Kotlin moveTo/lineTo (x, y), quadTo (control, end) and RectF(left, top, right, bottom) in the Swift order: the points,
        # addQuadCurve(to: end, control:), CGRect(x, y, width, height) and the corner sizes.
        expected = []
        for call, args in re.findall(r'(moveTo|lineTo|quadTo|addRoundRect|addRect)\((.*?)\)(?:,Path|$|;|\n)', top.group(1), re.M):
            v = [number(x) for x in re.findall(r'(\d+(?:\.\d+)?)f', args)]
            if call == 'quadTo':
                v = v[2:] + v[:2]
            elif call in ('addRoundRect', 'addRect'):
                v = [v[0], v[1], v[2] - v[0], v[3] - v[1]] + v[4:]
            expected += v
        actual = [number(v) for v in re.findall(r'\b(?:x|y|width|height|cornerWidth|cornerHeight): (\d+(?:\.\d+)?)', moves.group(1))]
        check(len(expected) == 42 and expected == actual, f'the classic tabletop path differs from Android: {expected} / {actual}')
        compared += 1
    else:
        check(False, 'the classic tabletop path was not found')
    rules = [
        # Court size and the two camera views (257e058, 0285385, a9140c3).
        (court, 'tilt = if (w > h) .52 else 1.72', scene, 'tilt = w > h ? 0.52 : 1.72'),
        (court, 'val margin=8*density;val board=(scoreboardHeight+16)*density', scene, 'let margin = 8.0, board = scoreboardHeight + 16'),
        (court, 'scale=min((w-2*margin)/(maxX-minX),(h-board-2*margin)/(maxY-minY)).toFloat()*.99f', scene,
         'scale = max(1, min((w - 2 * margin) / max(0.01, maxX - minX), (h - board - 2 * margin) / max(0.01, maxY - minY)) * 0.99)'),
        (court, 'for(pose in listOf(0,contactPose))', scene, 'for pose in [0, contactPose]'),
        (court, 'val foot=playerFoot(id,facing,mirror,seat,u,1f,::unit)', scene, 'playerFoot(id, facing, mirror: mirror, seat: s, u: 0, unitScale: 1, project: unit)'),
        (court, 'return PointF((v.x*kk).toFloat(),((v.y*tilt-lift(height))*kk).toFloat())', scene, 'return CGPoint(x: v.x * kk, y: (v.y * t - lift(height)) * kk)'),
        (court, 'getBoolean("close_camera",false)', read('MultiPong/MPPreferences.swift'), '"cross.closeCamera") == nil ? false'),
        (court, 'fun toggleCamera(){fullScreen=!fullScreen;context.getSharedPreferences("cross",0).edit().putBoolean("close_camera",fullScreen).apply()}',
         read('MultiPong/MPController.swift'), 'preferences.crossCloseCamera = actionCamera'),
        (android_blob(android, KT + 'multiplayer/PrivateMatchActivity.kt'), 'c.fullScreen=getSharedPreferences("cross",MODE_PRIVATE).getBoolean("close_camera",false)',
         read('MultiPong/MPController.swift'), 'court.fullScreen = preferences.crossCloseCamera'),
        # The close camera (a9140c3, 5375378).
        (android_blob(android, KT + 'cross/CrossCamera.kt'), 'val desired=if(close)minOf(1.48f,', scene, 'let desired = close ? max(1, min(1.48,'),
        (android_blob(android, KT + 'cross/CrossCamera.kt'), 'val k=(1-exp(-dt.coerceIn(0.0,.1)/(if(desired<zoom).20 else .65))).toFloat()', scene,
         'let k = 1 - exp(-min(0.1, max(0, dt)) / (desired < zoom ? 0.20 : 0.65))'),
        (android_blob(android, KT + 'cross/CrossCamera.kt'), 'dx=px*(1-zoom);dy=py*(1-zoom)', scene, 'dx = px * (1 - zoom); dy = py * (1 - zoom)'),
        (court, 'val visibleSeats=if(starting||preparing||shotAge<.42)g.seats.toList()', scene, 'if starting || preparing || shotAge < 0.42 { visible = Array(g.seats) }'),
        (court, 'listOfNotNull(receiver,engine.lastCommittedStrike?.seat?.takeIf{shotAge<.70})', scene,
         'visible = [engine.predictedReceiver, shotAge < 0.70 ? engine.lastCommittedStrike?.seat : nil].compactMap { $0 }'),
        (court, 'required.union(RectF(r.left-8*density,r.top-10*density,r.right+8*density,r.top+r.height()*.79f))', scene,
         'CGRect(x: Double(r.minX) - 8, y: Double(r.minY) - 10, width: Double(r.width) + 16, height: Double(r.height) * 0.79 + 10)'),
        (court, 'RectF(8*density,(scoreboardHeight+8)*density,width-8*density,height-8*density)', scene,
         'CGRect(x: 8, y: scoreboardHeight + 8, width: max(0, width - 16), height: max(0, height - scoreboardHeight - 16))'),
        # Grounded players (a9140c3).
        (court, 'val floor=project(g.fromLocal(seat,u,CrossGeometry.REACH+.05),0.0)', scene, 'let floor = project(g.fromLocal(seat, u, CrossGeometry.reach + 0.05), 0)'),
        (court, 'val inward=if(view.x>0)offsets.minOf{it.x} else offsets.maxOf{it.x}', scene, 'let inward = (view.x > 0 ? xs.min() : xs.max()) ?? 0'),
        (court, 'foot.y=floor.y+(unitScale*k(view.y)*.32).toFloat()', scene, 'foot.y = CGFloat(Double(floor.y) + unitScale * k(view.y) * 0.32)'),
        (atlas, 'val first=(f.visible.top+f.visible.height()*.60f).toInt()', scene, 'Int(top + height * Float(0.60))'),
        (atlas, 'val last=(f.visible.top+f.visible.height()*.68f).toInt()', scene, 'last = Int(top + height * Float(0.68))'),
        (atlas, 'if(alpha>=128){weight+=alpha;moment+=alpha*x}', scene, 'if a >= 128 { weight += Double(a); moment += Double(a) * Double(x) }'),
        (atlas, 'val top=(f.visible.bottom-f.visible.height()*.16f).toInt()', scene, 'Int(Float(f.visible.maxY) - Float(f.visible.height) * Float(0.16))'),
        (atlas, 'if(Color.alpha(a.image.getPixel(f.source.left+x,f.source.top+y))>=160)', scene, 'alpha.at(sourceX + x, sourceY + y) >= 160'),
        # Occlusion (0285385, 4969038, d376d64, 80fc74e, b0cdeb3, fcfd6b2) and the contact-racket filter (1fc4bc2).
        (court, 'style=Paint.Style.STROKE;strokeWidth=5*density;strokeJoin=Paint.Join.ROUND', scene, 'copy(strokingWithWidth: 5, lineCap: .butt, lineJoin: .round, miterLimit: 4)'),
        (court, 'val bodyMask=if(facing==PongPlayerAtlas.Facing.FRONT)tableBodyMaskShown else tableShown', scene, 'let bodyMask = facing == .front ? tableBodyMask : tablePath'),
        (court, 'if(facing==PongPlayerAtlas.Facing.FRONT && id in listOf("mia","minik","flare","kyra")){', scene,
         'if facing == .front && ["mia", "minik", "flare", "kyra"].contains(id) {'),
        (court, 'val waist=maxOf(foot.y-actorHeight*.48f,rendered.racket.y+rendered.radius*1.45f)', scene,
         'let waist = max(Double(foot.y) - actorHeight * 0.48, Double(rendered.racket.y) + rendered.radius * 1.45)'),
        (court, 'contactRackets.containsKey(it)&&engine.stroke(it).let{s->s.active&&!s.contacted && s.point.distance(engine.ballPosition)<.20}}', scene,
         'guard s.active && !s.contacted && s.point.distance(engine.ballPosition) < 0.20 else { continue }'),
        (court, 'val duration=(hit.ball.lift+sqrt(hit.ball.lift*hit.ball.lift+2*gravity*max(0.0,hit.ball.height)))/gravity', scene,
         'let duration = (hit.ball.lift + sqrt(hit.ball.lift * hit.ball.lift + 2 * gravity * max(0, hit.ball.height))) / gravity'),
        # The far name badge (9862dc6).
        (court, 'val left=g.toView(viewSeat,g.home(s)).x<-.05', scene, 'let left = homeView.x < -0.05'),
        (court, 'it.left-w/2-10*density else it.right+w/2+10*density,it.top+22*density', scene,
         'left ? Double(box.minX) - boxWidth / 2 - 10 : Double(box.maxX) + boxWidth / 2 + 10, y: Double(box.minY) + 22'),
        # The foreground foliage (3b52d51) is drawn after the camera, before the tags.
        (court, 'receptionCamera.end(canvas)\n        SunsetTerrace.foreground(this,canvas)\n        drawTags(canvas)', scene, 'renderForeground()\n        renderTags()'),
        # The classic court (a9140c3, 3b52d51, 4969038, d376d64, 5375378).
        (modern, 'val footOffset=max(1627f*scale,(NearPlayerProjection.imageY(.87)*scale).toFloat()-pose.racket.y)', classic,
         'let footOffset = max(1627 * worldScale, MPNearPlayerProjection.imageY(0.87) * worldScale - Double(racket))'),
        (modern, 'max(254*scale,h-10*d-footOffset)', classic, 'top = max(254 * worldScale, h - 10 - footOffset)'),
        (modern, 'val phase=when{!stroke.active->0;!stroke.contacted->1;stroke.age<.36->2;stroke.age<.52->3;else->0}', classic,
         'let phase = !stroke.active ? 0 : !stroke.contacted ? 1 : stroke.age < 0.36 ? 2 : stroke.age < 0.52 ? 3 : 0'),
        (modern, 'val height=min(520f*actorScale,max(1f,(table.top-8*resources.displayMetrics.density)/.82f))', classic,
         'let height = min(520 * worldScale, max(1, (tableTop - 8) / 0.82))'),
        (modern, 'val foot=PointF(x,table.top+190f*actorScale)', classic, 'y: tableTop + 190 * worldScale)'),
        (modern, 'canvas.drawOval(foot.x-height*.24f,foot.y-height*.025f,foot.x+height*.24f,foot.y+height*.035f,paint)', classic,
         'CGRect(x: Double(foot.x) - height * 0.24, y: Double(size.height) - (Double(foot.y) + height * 0.035),\n                                                      width: height * 0.48, height: height * 0.06)'),
        (modern, 'playerAtlas.drawMinikFrontHands(canvas,facingLeft,foot,height,phase)', classic, 'atlas.frontHands("minik", mirror: facingLeft, foot: foot, height: height, phase: phase)'),
        (modern, 'intArrayOf(0xffd7f4ed.toInt(),0xff6ba9af.toInt())', classic, '[color(0xffd7f4ed), color(0xff6ba9af)]'),
        (modern, 'canvas.drawRoundRect(table.left+3*scale,table.bottom-3*scale,table.right-3*scale,table.bottom+8*scale,5*scale,5*scale,paint)', classic,
         'CGRect(x: table.minX + 3 * scale, y: table.maxY - 3 * scale, width: table.width - 6 * scale, height: 11 * scale),\n                             cornerWidth: 5 * scale, cornerHeight: 5 * scale'),
        (modern, 'paint.color=0xfff4fff9.toInt();paint.strokeWidth=3*scale;paint.strokeCap=Paint.Cap.ROUND', classic,
         'c.setStrokeColor(color(0xfff4fff9)); c.setLineWidth(3 * scale); c.setLineCap(.round)'),
        (modern, 'val behindNear=ball.y<1.12', classic, 'ballNode.zPosition = behindFar ? 3.1 : behindNear ? 3.4 : 5'),
        (modern, 'canvas.drawBitmap(bitmap(R.drawable.ping_pong_arena),null,arena,spritePaint)', classic, 'floorNode.texture = texture("ping_pong_arena")'),
        (android_blob(android, KT + 'ReceptionCamera.kt'), 'x=width*.5f;y=height*.62f', scene, 'x = width * 0.5; y = height * 0.62'),
    ]
    for kotlin_source, kotlin, swift_source, swift in rules:
        check(kotlin in kotlin_source, f'Android changed: {kotlin[:70]}')
        check(swift in swift_source, f'iOS lacks the Android rule: {swift[:70]}')
    # The old values are gone.
    for old in ('tilt = w > h ? 0.72 : 1.28', 'CrossGeometry.reach + 0.34', 'let margin = 14.0', 'crossActionCamera', 'crossFullScreen'):
        check(old not in sources, f'MultiPong/ still has the pre-stage-2 {old}')
    check('ping_pong_arena_faded' not in classic, 'MPScene still draws the faded arena')
    return compared + len(rules)


# ---- Stage 3 (2026-11-09): playing â€” single tap, aiming, footwork and the loose ball, checked against Android STAGE1_COMMIT ----
# The same pinned commit (dd94c09): the input and post-point rules of 5375378, af84f72, ab089c5, fcfd6b2, c93e760, 6fcb446,
# d0bed3b and 971e958 must be Android's, number for number.

def check_stage3(android, sources):
    """Single-tap Standard/Starter, court-tap aiming, footwork, paddle recovery, double-tap sets and the loose ball after a point."""
    engine = android_blob(android, KT + 'cross/CrossEngine.kt')
    court = android_blob(android, KT + 'cross/CrossCourt.kt')
    shots = android_blob(android, KT + 'cross/CrossShots.kt')
    pose = android_blob(android, KT + 'cross/CrossPaddlePose.kt')
    practice = android_blob(android, KT + 'cross/CrossPractice.kt')
    loose = android_blob(android, KT + 'LooseBall.kt')
    modern = android_blob(android, KT + 'ModernGame.kt')
    modern_court = android_blob(android, KT + 'ModernCourt.kt')
    ios_engine = read('MultiPong/CrossEngine.swift')
    ios_scene = read('MultiPong/CrossScene.swift')
    ios_shots = read('MultiPong/CrossShots.swift')
    ios_pose = read('MultiPong/CrossPaddlePose.swift')
    ios_practice = read('MultiPong/CrossPractice.swift')
    ios_loose = read('MultiPong/MPLooseBall.swift')
    ios_classic = read('MultiPong/MPEngine.swift')
    ios_classic_scene = read('MultiPong/MPScene.swift')
    rules = [
        # The cross engine: footwork reach (6fcb446, 971e958), the double tap (971e958), court-tap aiming (d0bed3b), Standard aiming
        # (fcfd6b2), paddle recovery (d0bed3b) and the loose ball (5375378, af84f72).
        (engine, 'CrossGeometry.STRIKE_HALF + if(tapTargets && seats.any{it.kind==SeatKind.LOCAL && it.characterId.isNotBlank()}) .50 else 0.0',
         ios_engine, 'CrossGeometry.strikeHalf + (tapTargets && character ? 0.50 : 0)'),
        (engine, 'it.v in CrossGeometry.STRIKE_NEAR..CrossGeometry.STRIKE_FAR &&\n            it.u in -CrossGeometry.STRIKE_HALF..localFootworkRight',
         ios_engine, 'at.v >= CrossGeometry.strikeNear && at.v <= CrossGeometry.strikeFar && at.u >= -CrossGeometry.strikeHalf && at.u <= localFootworkRight'),
        (engine, 'private fun rest(local: Int, point: Vec) {\n        if (!inFootworkZone(local, point)) return', ios_engine,
         'private func rest(_ local: Int, _ point: MPPoint) {\n        if !inFootworkZone(local, point) { return }'),
        (engine, 'if (point != null && inFootworkZone(local, point)) { practicePaddlePlaced=true;movePaddle(local, point) }', ios_engine,
         'if let point, inFootworkZone(local, point) { practicePaddlePlaced = true; movePaddle(local, point) }'),
        (engine, 'private fun begin(seat: Int, point: Vec, height: Double, left: Boolean) {\n        strokes[seat].start(++serial, left, point, height)',
         ios_engine, 'private func begin(_ seat: Int, _ point: MPPoint, _ height: Double, left: Bool) {\n        serial += 1'),
        (engine, 'val s = strokes[seat]\n        if (s.contacted) return\n        s.contact(point, height)', ios_engine,
         'private func contact(_ seat: Int, _ point: MPPoint, _ height: Double) {\n        if strokes[seat].contacted { return }'),
        (engine, 'setTapPending=teams!=null && !receivingSet && !referee.mayServe(local)\n            if(setTapPending)teamHoldUntil=ticks+40', ios_engine,
         'setTapPending = teams != nil && !receivingSet && !referee.mayServe(local)\n            if setTapPending { teamHoldUntil = ticks + 40 }'),
        (engine, 'tappedAim = null; aimDp = 0.0; gestureSpeed = 0.0;', ios_engine, 'tappedAim = nil; aimDp = 0; gestureSpeed = 0;'),
        (engine, 'if(!tapTargets && control==CrossControl.BEGINNER && down)tappedAim=otherCourt(local,point)', ios_engine,
         'if !tapTargets && control == .beginner && down { tappedAim = otherCourt(local, point) }'),
        (engine, 'if(abs(dragDp.x)>12)tappedAim=null', ios_engine, 'if abs(drag.x) > 12 { tappedAim = nil }'),
        (engine, 'if(setTapPending && dragDp.length>12){setTapPending=false;teamHoldUntil=0L}', ios_engine,
         'if setTapPending && drag.length > 12 { setTapPending = false; teamHoldUntil = 0 }'),
        (engine, 'geometry.owner(point)==teammate(local) && teamFlight?.friendlyHits==0){teamPass=true;teamHoldUntil=0L;setTapPending=false}', ios_engine,
         'geometry.owner(point) == teammate(local), teamFlight?.friendlyHits == 0 {\n            teamPass = true; teamHoldUntil = 0; setTapPending = false'),
        (engine, 'if(setTapPending && !cancelled && !teamLift)teamHoldUntil=ticks+40\n        if(cancelled)teamHoldUntil=0L\n        setTapPending=false', ios_engine,
         'if setTapPending && !cancelled && !teamLift { teamHoldUntil = ticks + 40 }\n        if cancelled { teamHoldUntil = 0 }\n        setTapPending = false'),
        (engine, 'if (cancelled) { pendingTap = null; tappedAim=null }', ios_engine, 'if cancelled { pendingTap = nil; tappedAim = nil }'),
        (engine, 'if(playable() && inFootworkZone(local,point))movePaddle(local,point)', ios_engine,
         'if playable() && inFootworkZone(local, point) { movePaddle(local, point) }'),
        (engine, 'if(!playable() || control !in listOf(CrossControl.STARTER,CrossControl.STANDARD) || predictedReceiver!=local || receivingSet)return false',
         ios_engine, 'if !playable() || (control != .starter && control != .standard) || predictedReceiver != local || receivingSet { return false }'),
        (engine, 'return at.v >= (if(control==CrossControl.STARTER).25 else .55) &&\n            abs(at.u-geometry.toLocal(local,restingPaddle).u)<=physics.tapSpatialTolerance',
         ios_engine, 'return at.v >= (control == .starter ? 0.25 : 0.55) &&\n            abs(at.u - geometry.toLocal(local, restingPaddle).u) <= physics.tapSpatialTolerance'),
        (engine, 'if(!canAimReturn())return false\n            tappedAim=otherCourt(local,target)\n            aimDp=0.0;gestureSpeed=0.0\n            tap(local,restingPaddle)',
         ios_engine, 'if !canAimReturn() { return false }\n            tappedAim = otherCourt(local, target)\n            aimDp = 0; gestureSpeed = 0\n            tap(local, restingPaddle)'),
        (engine, 'if(drag.isFinite()){aimDp=drag;if(abs(drag)>12)tappedAim=null}', ios_engine, 'if drag.isFinite { aimDp = drag; if abs(drag) > 12 { tappedAim = nil } }'),
        (engine, 'p.length.isFinite() && geometry.owner(p)?.let { it!=local && teams?.same(it,local)!=true }==true', ios_engine,
         'guard let p = point, p.length.isFinite, let owner = geometry.owner(p), owner != local, teams?.same(owner, local) != true else { return nil }'),
        (engine, 'selectedAim ?: (if(abs(aimDp)<=12)otherCourt(local,tap)else null) ?: aim.point', ios_engine, 'second: selectedAim ?? tapped ?? aim.point'),
        (engine, 'if (pendingTap != null && s.age >= s.total && !s.contacted) { pendingTap = null; tappedAim=null }', ios_engine,
         'if pendingTap != nil && s.age >= s.total && !s.contacted { pendingTap = nil; tappedAim = nil }'),
        (engine, 'pendingTap = null; tappedAim=null; aimDp = 0.0; gestureSpeed = 0.0; gestureAnchor = null;practicePaddlePlaced=false', ios_engine,
         'pendingTap = nil; tappedAim = nil; aimDp = 0; gestureSpeed = 0; gestureAnchor = nil; practicePaddlePlaced = false'),
        (engine, 'geometry.fromLocal(mate,0.0,if(teamLift)CrossShots.SET_DEPTH else .88),teamLift)', ios_engine,
         'geometry.fromLocal(mate, 0, teamLift ? CrossShots.setDepth : 0.88), lob: teamLift)'),
        (engine, 'if(shouldSet)CrossShots.SET_DEPTH else .88', ios_engine, 'shouldSet ? CrossShots.setDepth : 0.88'),
        (engine, 'variation = if(automaticContact)sway() else 0.0)', ios_engine, 'variation: automaticContact ? sway() : 0)'),
        (engine, 'val selected=(selectedAim ?: tappedAim)?.takeUnless', ios_engine, 'var selected = selectedAim ?? tappedAim'),
        (engine, 'return (selectedAim ?: tappedAim)?.let(geometry::owner) ?: aims.aim(local, aimDrag(), 0.0, sender = referee.striker).opponent', ios_engine,
         'if let owner = (selectedAim ?? tappedAim).flatMap({ geometry.owner($0) }) { return owner }'),
        (engine, 'teamLift=true;teamPass=true;teamHoldUntil=0L;setTapPending=false;pendingTap=null', ios_engine,
         'teamLift = true; teamPass = true; teamHoldUntil = 0; setTapPending = false; pendingTap = nil'),
        (engine, 'practicePaddlePlaced=true\n        return true', ios_engine, 'practicePaddlePlaced = true\n        return true'),
        (engine, 'return CrossShots.raisedPass(geometry,physics,from,height,to,pace)', ios_engine,
         'return CrossShots.raisedPass(geometry, physics, from: from, height: height, target: to, pace: pace)'),
        (engine, 'teamLift=false;teamPass=false;teamHoldUntil=0L;setTapPending=false', ios_engine, 'teamLift = false; teamPass = false; teamHoldUntil = 0; setTapPending = false'),
        (engine, 'val ballVisible get()=referee.phase!=RallyPhase.AWAITING_SERVE || strokes[referee.server].active', ios_engine,
         'var ballVisible: Bool { referee.phase != .awaitingServe || strokes[referee.server].active }'),
        (engine, 'val velocity=if(s.stopped)previous?.velocity ?: s.velocity else s.velocity', ios_engine,
         'let velocity = s.stopped ? (previous?.velocity ?? s.velocity) : s.velocity'),
        (engine, 'val net=netAge<.02', ios_engine, 'let net = netAge < 0.02'),
        (engine, 'if(net)velocity*(-.2)else velocity,if(s.stopped)previous?.lift ?: s.lift else s.lift,\n            floor=-.38,onTable=geometry::onTable,classicNet=false)',
         ios_engine, 'net ? velocity * -0.2 : velocity, s.stopped ? (previous?.lift ?? s.lift) : s.lift,\n                                floor: -0.38, onTable: { table.onTable($0) }, classicNet: false)'),
        (engine, 'private fun coast() { coastBall();looseBall?.advance(STEP,physics,emptyList()) }', ios_engine,
         'private func coast() { coastBall(); looseBall?.advance(CrossEngine.step, physics) }'),
        (engine, 'private fun stepBall() {\n        beforeBallStep=ball.state', ios_engine, 'private func stepBall() {\n        beforeBallStep = ball.state'),
        (engine, 'private fun resolved(outcome: RallyOutcome) {\n        coastBall()', ios_engine, 'private func resolved(_ outcome: CrossRallyOutcome) {\n        coastBall()'),
        (engine, 'looseBall=null;beforeBallStep=null', ios_engine, 'looseBall = nil; beforeBallStep = nil'),
        (engine, 'beforeBallStep=ball.state\n        ball.restore(state.ball)\n        if(next.phase==RallyPhase.RESOLVED){\n            if(next.rallyId!=old.rallyId)looseBall=null\n            coastBall()\n        }else looseBall=null',
         ios_engine, 'beforeBallStep = ball.state\n        ball.restore(state.ball)'),
        (engine, 'if(next.rallyId!=old.rallyId)looseBall=null', ios_engine,
         'if next.phase == .resolved {\n            if next.rallyId != old.rallyId { looseBall = nil }\n            coastBall()\n        } else { looseBall = nil }'),
        (engine, 'reconciliation = before - (looseBall?.position ?: ball.position)', ios_engine, 'reconciliation = before - (looseBall?.position ?? ball.position)'),
        (engine, 'val renderBallPosition get() = (looseBall?.position ?: ball.position) + reconciliation * (reconciliationAge / BLEND)', ios_engine,
         'var renderBallPosition: MPPoint { (looseBall?.position ?? ball.position) + reconciliation * (reconciliationAge / CrossEngine.blend) }'),
        (shots, 'const val SET_DEPTH = .88', ios_shots, 'static let setDepth = 0.88'),
        (shots, 'val time=(normal+.55).coerceIn(1.65,3.0)\n        return Launch((target-from)*(1/time),(.5*t.gravity*time*time-height)/time)', ios_shots,
         'let time = (normal + 0.55).mpClamp(1.65, 3.0)\n        return CrossLaunch(velocity: (target - from) * (1 / time), lift: (0.5 * t.gravity * time * time - height) / time)'),
        (pose, 'if(!stroke.active || !stroke.contacted)return rest to 0.0', ios_pose, 'if !stroke.active || !stroke.contacted { return (rest, 0) }'),
        (pose, 'val holdEnd=minOf(stroke.impactAt+.07,stroke.total)', ios_pose, 'let holdEnd = min(stroke.impactAt + 0.07, stroke.total)'),
        (pose, 'val t=((stroke.age-holdEnd)/(stroke.total-holdEnd).coerceAtLeast(.001)).coerceIn(0.0,1.0)', ios_pose,
         'let t = ((stroke.age - holdEnd) / max(0.001, stroke.total - holdEnd)).mpClamp(0, 1)'),
        (pose, 'val eased=t*t*(3-2*t)\n        return (stroke.point*(1-eased)+rest*eased) to stroke.height*(1-eased)', ios_pose,
         'let eased = t * t * (3 - 2 * t)\n        return (stroke.point * (1 - eased) + rest * eased, stroke.height * (1 - eased))'),
        (practice, 'localFootworkRight=CrossGeometry.STRIKE_HALF+.50', ios_practice, 'localFootworkRight: CrossGeometry.strikeHalf + 0.50'),
        (practice, 'if(stage.aimed && nextIn<=0 && engine.selectedAim==null &&\n      engine.referee.phase==RallyPhase.AWAITING_SERVE)return', ios_practice,
         'if stage.aimed && nextIn <= 0 && engine.selectedAim == nil && engine.referee.phase == .awaitingServe { return }'),
        # The cross court: the post-point draw order and ball (5375378), paddle recovery (d0bed3b), the Standard gesture (fcfd6b2,
        # d0bed3b), the learners' drag (c93e760, 6fcb446, 971e958) and the double tap (971e958).
        (court, 'if(engine.postPointBall){\n            drawNets(canvas)\n            val ballDepth=g.toView(viewSeat,engine.renderBallPosition).y', ios_scene,
         'netsNode.zPosition = 1.9\n            func depthOf(_ seat: Int) -> Double { g.toView(viewSeat, g.home(seat)).y }\n            let ball = g.toView(viewSeat, engine.renderBallPosition).y'),
        (court, 'if(!drawn && ballDepth<g.toView(viewSeat,g.home(seat)).y){', ios_scene, 'if drawn == nil && ball < depthOf(seat) { drawn = depth - 0.05 }'),
        (court, 'if(engine.postPointBall)return PointF()', ios_scene, 'if engine.postPointBall { return .zero }'),
        (court, 'fun renderedBallPoint():PointF=screen(engine.renderBallPosition,engine.renderHeight)', ios_scene,
         'let b = screen(engine.renderBallPosition, engine.renderHeight), o = ballOffset()'),
        (court, 'if(!engine.ballVisible)return\n        val ground = engine.renderBallPosition\n        val h = engine.renderHeight\n        if(h<0 && g.onTable(ground))return',
         ios_scene, 'let ground = engine.renderBallPosition\n        let h = engine.renderHeight\n        guard engine.ballVisible, !(h < 0 && g.onTable(ground)) else {'),
        (court, 'val radius = size * BALL * (1 + h.coerceIn(0.0, .4).toFloat() * .35f)', ios_scene, 'let radius = unit * CrossScene.ballSize * (1 + h.mpClamp(0, 0.4) * 0.35)'),
        (court, 'val lifted = (h.coerceIn(0.0,1.5) / 1.5).toFloat()\n        if (h>=0 && engine.geometry.onTable(ground)) {', ios_scene,
         'let raised = h.mpClamp(0, 1.5) / 1.5\n        if h >= 0 && g.onTable(ground) {'),
        (court, 'private fun lift(h: Double) = if(h<0)h*LIFT_MAX/LIFT_SCALE else LIFT_MAX * (1 - exp(-h / LIFT_SCALE))', ios_scene,
         'h < 0 ? h * CrossScene.liftMax / CrossScene.liftScale : CrossScene.liftMax * (1 - exp(-h / CrossScene.liftScale))'),
        (court, 'val pose = CrossPaddlePose.at(stroke,at)\n        val p = pose.first\n        val q = screen(p,pose.second)', ios_scene,
         'let pose = CrossPaddlePose.at(stroke, at)\n        let p = pose.point\n        paddleNode.isHidden = false\n        paddleNode.position = sk(unpanned(p, pose.height))'),
        (court, 'val u=if(engine.tapTargets&&seat==viewSeat)local.u.coerceIn(-CrossGeometry.STRIKE_HALF,engine.localFootworkRight)else local.u.coerceIn(-.48,.48)',
         ios_scene, 'let u = engine.tapTargets && seat == viewSeat ? local.u.mpClamp(-CrossGeometry.strikeHalf, engine.localFootworkRight) : local.u.mpClamp(-0.48, 0.48)'),
        (court, 'standardGesture=engine.control in listOf(CrossControl.STARTER,CrossControl.STANDARD) &&\n                engine.localSeat?.let{!engine.referee.mayServe(it)}==true && !engine.receivingSet && !engine.tapTargets',
         ios_scene, 'standardGesture = (engine.control == .starter || engine.control == .standard) && !serving && !engine.receivingSet && !engine.tapTargets'),
        (court, 'val startsOnBall=hypot(event.x-visibleBall.x,event.y-visibleBall.y)<max(44*density,scale*.16f)', ios_scene,
         'let startsOnBall = hypot(Double(p.x - visibleBall.x), Double(p.y - visibleBall.y)) < max(44, scale * 0.16)'),
        (court, 'practiceDrag=engine.tapTargets && !(engine.receivingSet && startsOnBall) &&', ios_scene,
         'practiceDrag = engine.tapTargets && !(engine.receivingSet && startsOnBall) && !serving && bodyBounds[viewSeat]?.contains(p) == true'),
        (court, 'standardWidth=abs(screen(g.fromView(viewSeat,Vec(v.x+1,v.y))).x-screen(standardAnchor).x).coerceAtLeast(1f)', ios_scene,
         'standardWidth = max(1, abs(Double(screen(g.fromView(viewSeat, MPPoint(anchor.x + 1, anchor.y))).x - screen(standardAnchor).x)))'),
        (court, 'raisedTap=event.eventTime-lastTapAt in 1..android.view.ViewConfiguration.getDoubleTapTimeout().toLong() && hypot(event.x-lastTapX,event.y-lastTapY)<56*density && engine.liftToTeammate()',
         ios_scene, 'raisedTap = gap >= 0.001 && gap <= CrossScene.doubleTapTimeout && hypot(p.x - lastTapPoint.x, p.y - lastTapPoint.y) < 56 && engine.liftToTeammate()'),
        (court, 'if(raisedTap)return // the second tap armed a set', ios_scene, 'if raisedTap { return }\n        if standardGesture { standardTouch(p, down: down, up: up); return }'),
        (court, 'visibleDistance<max(44*density,scale*.16f) && visibleDistance<hypot(x-groundBall.x,y-groundBall.y)', ios_scene,
         'visibleDistance < max(44, scale * 0.16) && visibleDistance < hypot(Double(p.x - groundBall.x), Double(p.y - groundBall.y))'),
        (court, 'world(groundBall.x+x-rawBall.x-offset.x,groundBall.y+y-rawBall.y-offset.y)', ios_scene,
         'world(Double(groundBall.x + p.x - rawBall.x - offset.x), Double(groundBall.y + p.y - rawBall.y - offset.y))'),
        (court, 'g.fromLocal(viewSeat,(at.u+(x-downX)/standardWidth).coerceIn(-CrossGeometry.STRIKE_HALF,engine.localFootworkRight),at.v)', ios_scene,
         'g.fromLocal(viewSeat, (at.u + Double(p.x - downPoint.x) / standardWidth).mpClamp(-CrossGeometry.strikeHalf, engine.localFootworkRight), at.v)'),
        (court, 'p.u.coerceIn(-CrossGeometry.STRIKE_HALF,engine.localFootworkRight),\n                p.v.coerceIn(CrossGeometry.STRIKE_NEAR,CrossGeometry.STRIKE_FAR))else projected',
         ios_scene, 'at.u.mpClamp(-CrossGeometry.strikeHalf, engine.localFootworkRight),\n                                                                    at.v.mpClamp(CrossGeometry.strikeNear, CrossGeometry.strikeFar)) : projected'),
        (court, 'if(practiceDrag && engine.receivingSet){engine.moveOnly(point);return}', ios_scene, 'if practiceDrag && engine.receivingSet { engine.moveOnly(point); return }'),
        (court, 'standardDragged=standardDragged || hypot(x-downX,y-downY)>12*density', ios_scene,
         'standardDragged = standardDragged || hypot(p.x - downPoint.x, p.y - downPoint.y) > 12'),
        (court, 'val speed=hypot((tracker?.getXVelocity(pointerId)?:0f).toDouble(),(tracker?.getYVelocity(pointerId)?:0f).toDouble())/standardWidth', ios_scene,
         'let speed = hypot(Double(finger.dx), Double(finger.dy)) / standardWidth'),
        (court, 'val u=(anchor.x+(x-downX)/standardWidth).coerceIn(-CrossGeometry.STRIKE_HALF,CrossGeometry.STRIKE_HALF)\n                engine.moveOnly(g.fromView(viewSeat,Vec(u,anchor.y.coerceIn(CrossGeometry.STRIKE_NEAR,CrossGeometry.STRIKE_FAR))))',
         ios_scene, 'let u = (anchor.x + Double(p.x - downPoint.x) / standardWidth).mpClamp(-CrossGeometry.strikeHalf, CrossGeometry.strikeHalf)\n                engine.moveOnly(g.fromView(viewSeat, MPPoint(u, anchor.y.mpClamp(CrossGeometry.strikeNear, CrossGeometry.strikeFar))))'),
        (court, 'engine.aimReturn(0.0,0.0,true,world(x,y))', ios_scene, 'engine.aimReturn(drag: 0, speed: 0, start: true, target: world(Double(p.x), Double(p.y)))'),
        # The loose ball (5375378, ab089c5).
        (loose, 'val floor:Double=-.85, private val onTable:(Vec)->Boolean={it.inside}, private val classicNet:Boolean=true, private val farEnd:Double?=null',
         ios_loose, 'floor: Double = -0.85,\n         onTable: @escaping (MPPoint) -> Bool = { $0.inside }, classicNet: Bool = true, farEnd: Double? = nil'),
        (loose, 'var left=delta.coerceIn(0.0,.1)\n  while(left>1e-9){val dt=min(left,1.0/240);left-=dt;step(dt,t,bodies)}', ios_loose,
         'var left = delta.mpClamp(0, 0.1)\n        while left > 1e-9 { let dt = min(left, 1.0 / 240); left -= dt; step(dt, t, bodies) }'),
        (loose, 'if(farEnd!=null && farCoastRemaining==null && position.y<=farEnd && velocity.y<0){\n   farCoastRemaining=.4', ios_loose,
         'if let farEnd, farCoastRemaining == nil, position.y <= farEnd, velocity.y < 0 {\n            farCoastRemaining = 0.4'),
        (loose, 'if(speed>.9)velocity=Vec(velocity.x*.9/speed,velocity.y*.9/speed)', ios_loose,
         'if speed > 0.9 { velocity = MPPoint(velocity.x * 0.9 / speed, velocity.y * 0.9 / speed) }'),
        (loose, 'val travel=if(remaining==null)dt else if(remaining<=0)0.0 else min(dt,remaining).let{it*(1-.5*it/remaining)}', ios_loose,
         'if remaining <= 0 { travel = 0 } else { let part = min(dt, remaining); travel = part * (1 - 0.5 * part / remaining) }'),
        (loose, 'val factor=if(remaining<=0)0.0 else (1-dt/remaining).coerceAtLeast(0.0)', ios_loose, 'let factor = remaining <= 0 ? 0 : max(0, 1 - dt / remaining)'),
        (loose, 'farCoastRemaining=(remaining-dt).coerceAtLeast(0.0)\n   position=position.copy(y=max(position.y,farEnd!!-.20))', ios_loose,
         'farCoastRemaining = max(0, remaining - dt)\n            position = MPPoint(position.x, max(position.y, farEnd - 0.20))'),
        (loose, 'height+=lift*dt-.5*t.gravity*dt*dt;lift-=t.gravity*dt', ios_loose, 'height += lift * dt - 0.5 * t.gravity * dt * dt; lift -= t.gravity * dt'),
        (loose, 'if(length<1e-8){nx=0.0;ny=if(before.y<b.y)-1.0 else 1.0}else{nx/=length;ny/=length}', ios_loose,
         'if length < 1e-8 { nx = 0; ny = before.y < b.y ? -1 : 1 } else { nx /= length; ny /= length }'),
        (loose, 'velocity=Vec(velocity.x-1.50*inward*nx,velocity.y-1.50*inward*ny)', ios_loose,
         'velocity = MPPoint(velocity.x - 1.50 * inward * nx, velocity.y - 1.50 * inward * ny)'),
        (loose, 'val radial=sqrt(dx*dx+dy*dy).coerceAtLeast(.001)\n    position=Vec(b.x+(position.x-b.x)/radial*1.002,b.y+(position.y-b.y)/radial*1.002)\n    bodyHits++;lastBody=b;bodyCooldown=.08',
         ios_loose, 'let radial = max(sqrt(dx * dx + dy * dy), 0.001)\n                position = MPPoint(b.x + (position.x - b.x) / radial * 1.002, b.y + (position.y - b.y) / radial * 1.002)\n                bodyHits += 1; lastBody = b; bodyCooldown = 0.08'),
        (loose, 'position=Vec(position.x,.5+if(before.y<.5)-.001 else .001)\n   velocity=Vec(velocity.x*.7,-velocity.y*.2)', ios_loose,
         'position = MPPoint(position.x, 0.5 + (before.y < 0.5 ? -0.001 : 0.001))\n            velocity = MPPoint(velocity.x * 0.7, -velocity.y * 0.2)'),
        (loose, "if(!onTable(before) && onTable(position) && height in -.045..0.0){\n   velocity=if(before.y !in 0.0..1.0)velocity.copy(y=-velocity.y*.4) else velocity.copy(x=-velocity.x*.4)",
         ios_loose, 'if !onTable(before) && onTable(position) && height >= -0.045 && height <= 0 {\n            velocity = !(before.y >= 0 && before.y <= 1) ? MPPoint(velocity.x, -velocity.y * 0.4) : MPPoint(-velocity.x * 0.4, velocity.y)'),
        (loose, 'val table=onTable(position) && z>=-1e-6', ios_loose, 'let table = onTable(position) && z >= -1e-6'),
        (loose, 'lift=if(impact<.16)0.0 else impact*if(table)t.bounceRestitution else .42\n   velocity=Vec(velocity.x*.82,velocity.y*.82)', ios_loose,
         'lift = impact < 0.16 ? 0 : impact * (table ? t.bounceRestitution : 0.42)\n            velocity = MPPoint(velocity.x * 0.82, velocity.y * 0.82)'),
        (loose, 'val rolling=abs(height-ground)<.002 && abs(lift)<.16\n  val drag=exp(-dt*if(rolling)5.0 else .18)', ios_loose,
         'let rolling = abs(height - ground) < 0.002 && abs(lift) < 0.16\n        let drag = exp(-dt * (rolling ? 5.0 : 0.18))'),
        (loose, 'if(rolling && hypot(velocity.x,velocity.y)<.025){velocity=Vec(0.0,0.0);lift=0.0;settled=true}', ios_loose,
         'if rolling && hypot(velocity.x, velocity.y) < 0.025 { velocity = .zero; lift = 0; settled = true }'),
        # The classic engine and court (5375378, af84f72, ab089c5, fcfd6b2).
        (modern, 'if(lastResolution?.fault==Fault.NET)Vec(f.velocity.x*.7,-f.velocity.y*.2)else f.velocity,\n            f.verticalVelocity,floor=-2.03,farEnd=0.0)}',
         ios_classic, 'lastResolution?.fault == .net ? MPPoint(f.velocity.x * 0.7, -f.velocity.y * 0.2) : f.velocity\n        looseBall = MPLooseBall(f.position, f.height, velocity, f.lift, floor: -2.03, farEnd: 0)'),
        (modern, 'val ballVisible get()=flight!=null || looseBall!=null', ios_classic, 'var ballVisible: Bool { flight != nil || looseBall != nil }'),
        (modern, 'val renderHeight get()=looseBall?.height ?: flight?.height ?: .055', ios_classic, 'var renderHeight: Double { looseBall?.height ?? flight?.height ?? 0.055 }'),
        (modern, 'looseBall?.advance(delta,tuning,emptyList())', ios_classic, 'looseBall?.advance(delta, tuning)'),
        (modern, 'val tapPrepared=control==Control.TAP && pendingTap!=null && !childStroke.contacted && childStroke.age>=.04 && childStroke.age<=childStroke.total',
         ios_classic, 'let tapPrepared = !level.pro && pendingTap != nil && !childStroke.contacted && childStroke.age >= 0.04 && childStroke.age <= childStroke.total'),
        (modern, 'if (!automaticContact && (tapPrepared || control==Control.SWIPE && childStroke.contactWindow) && childReturnOpen) {', ios_classic,
         'if !automaticContact && (tapPrepared || level.pro && childStroke.contactWindow) && childReturnOpen {'),
        (modern, 'if (childStroke.age > childStroke.total && !childStroke.contacted && pendingTap != null) { pendingTap = null; status = GameStatus.MISSED }',
         ios_classic, 'if childStroke.age > childStroke.total && !childStroke.contacted && pendingTap != nil { pendingTap = nil; status = "MISSED" }'),
        (modern, 'lastResolution = result; childReturnOpen = false; awaitingServe = false\n        coastBall()', ios_classic,
         'lastResolution = result; childReturnOpen = false; awaitingServe = false\n        coastBall()'),
        (modern, 'if (!awaitingServe && point.y<.5) return', ios_classic, 'if !awaitingServe && point.y < 0.5 { return }'),
        (modern, 'else if (childReturnOpen || flight?.let { !it.resolved && it.striker==Player.MINIK && it.position.y>=.60 }==true) {', ios_classic,
         'else if childReturnOpen || flight.map({ !$0.resolved && $0.striker == .minik && $0.position.y >= 0.60 }) == true {'),
        (modern, 'val target=Vec(point.x,point.y.coerceIn(.78,.96))', ios_classic, 'let target = MPPoint(point.x, point.y.mpClamp(0.78, 0.96))'),
        (modern, 'if(cancelled)pendingTap=null', ios_classic, 'if cancelled { pendingTap = nil }'),
        (modern, 'if(!playable() || awaitingServe || pendingServe!=null || !point.strikeZone)return\n        restingPaddle=point;restingPaddleHeight=0.0;paddle=point',
         ios_classic, 'if !playable || awaitingServe || pendingServe != nil || !point.strikeZone { return }\n        restingPaddle = point; restingHeight = 0; paddle = point'),
        (modern, 'it.position.y>=.60 && abs(restingPaddle.x-it.position.x)<=tuning.tapSpatialTolerance', ios_classic,
         '$0.position.y >= 0.60 && abs(restingPaddle.x - $0.position.x) <= tuning.tapSpatialTolerance'),
        (modern, 'if(start){if(!canAimReturn())return false;touch(restingPaddle)}', ios_classic, 'if start { if !canAimReturn() { return false }; touch(restingPaddle) }'),
        (modern, 'if(displacement.isFinite())tapAim=(displacement/.085).coerceIn(-2.0,2.0)', ios_classic,
         'if displacement.isFinite { tapAim = (displacement / 0.085).mpClamp(-2, 2) }'),
        (modern, 'val before=renderBallPosition', ios_classic, 'let before = renderedBall'),
        (modern, 'if(s.pointDelay!=null || s.score.winner!=null){if(!sameFinishedPoint)looseBall=null;coastBall()}else looseBall=null', ios_classic,
         'if s.pointDelay != nil || s.score.winner != nil { if !sameFinishedPoint { looseBall = nil }; coastBall() } else { looseBall = nil }'),
        (modern, 'val displayed=looseBall?.position ?: ballPosition', ios_classic, 'let displayed = looseBall?.position ?? ball'),
        (modern, 'looseBall=null;flight=Flight.restore(s)', ios_classic, 'looseBall = nil; flight = f'),
        (modern_court, 'val behindFar=engine.postPointBall && ball.y<-.10\n        val behindNear=ball.y<1.12', ios_classic_scene,
         'let behindFar = engine.postPointBall && p.y < -0.10, behindNear = p.y < 1.12\n        ballNode.zPosition = behindFar ? 3.1 : behindNear ? 3.4 : 5'),
        (modern_court, 'if(!engine.ballVisible || (engine.renderHeight<0 && ball.inside))return', ios_classic_scene,
         'ballNode.isHidden = !engine.ballVisible || (drawnHeight < 0 && p.inside)'),
        (modern_court, 'if(engine.ballVisible && engine.renderHeight>=0 && ball.inside){', ios_classic_scene,
         'shadowNode.isHidden = !(engine.ballVisible && drawnHeight >= 0 && p.inside)'),
        (modern_court, 'standardGesture=engine.control==Control.TAP && !engine.automaticContact && !engine.awaitingServe', ios_classic_scene,
         'standardGesture = !engine.level.pro && !engine.automaticContact && !engine.awaitingServe'),
        (modern_court, 'standardDragged=standardDragged || hypot(x-standardDownX,y-standardDownY)>12*resources.displayMetrics.density', ios_classic_scene,
         'standardDragged = standardDragged || hypot(location.x - standardDown.x, location.y - standardDown.y) > 12'),
        (modern_court, 'val displacement=(x-standardAimX)/table.width().toDouble()', ios_classic_scene,
         'let displacement = Double(location.x - standardAimX) / max(1, tableWidth)'),
        (modern_court, 'engine.moveOnly(Vec((standardAnchor.x+(x-standardDownX)/table.width()).coerceIn(.02,.98),standardAnchor.y))', ios_classic_scene,
         'engine.moveOnly(MPPoint((standardAnchor.x + Double(location.x - standardDown.x) / max(1, tableWidth)).mpClamp(0.02, 0.98), standardAnchor.y))'),
        (modern_court, '}else if(event.actionMasked==MotionEvent.ACTION_UP)engine.aimReturn(0.0,Vec(0.0,0.0),true)', ios_classic_scene,
         '} else if up { engine.aimReturn(0, movement: .zero, start: true) }'),
        (modern_court, 'table.set(x + 93 * horizontalScale, y + 186 * scale, x + 847 * horizontalScale, y + 1437 * scale)', ios_classic_scene,
         'let tableWidth = MPProjection.tableWidth * horizontalScale, tableHeight = (MPProjection.bottom - MPProjection.top) * worldScale'),
        (modern_court, 'return arena.top + ((ground-height*(CourtProjection.TABLE_BOTTOM-CourtProjection.TABLE_TOP)*.075)/1672*arena.height()).toFloat()',
         ios_classic_scene, 'let y = ground - height * (MPProjection.bottom - MPProjection.top) * 0.075'),
    ]
    for kotlin_source, kotlin, swift_source, swift in rules:
        check(kotlin in kotlin_source, f'Android changed: {kotlin[:70]}')
        check(swift in swift_source, f'iOS lacks the Android rule: {swift[:70]}')
    # The superseded behaviour is gone.
    for old, source, label in [('if seat == localSeat { rest(seat, point) }', ios_engine, 'a swing or contact still moves the stance'),
                               ('teamHoldUntil = ticks + 34', ios_engine, 'the 34-substep team hold'),
                               ('gap <= 0.280', ios_scene, 'the fixed 280 ms double tap'),
                               ('private func coast() { if !ball.stopped { ball.step(CrossEngine.step) } }', ios_engine, 'the ball still steps after a point'),
                               ('min(2.55, CrossShots.flightTime', ios_engine, 'the old raised pass'),
                               ('guard awaitingServe || point.strikeZone else { return }', ios_classic, 'the classic strike-zone tap gate'),
                               ('childStroke.age > childStroke.windowEnd', ios_classic, 'the classic tap expiring at the window end')]:
        check(old not in source, f'MultiPong/ still has {label}')
    check(engine.count('localFootworkRight') == 2 and 'fun aimReturn(drag:Double, speed:Double, start:Boolean, target:Vec?=null):Boolean' in engine,
          'Android aimReturn/localFootworkRight changed')
    return len(rules)


# ---- Stage 4 (2026-11-09): rooms, checked against Android STAGE1_COMMIT --------------------------------------------------------
# Rematches and the Loading page (5375378, 3f13c40), saved friendly and team lineups and clockwise seats (1fc4bc2), Back's Save
# and exit / Exit without saving / Stay with explicit saves and the Firebase lobby rollback (452d82c, 83b050d, 9adf1f1),
# two-player tournaments (bb8acda), and the Firebase rules (1fc4bc2: the friendly host may create and start a house-only final).

STAGE4_RULES = [
    ('firebase-setup/merged-database-rules.json', 'Tests/MultiPongFirebase/rules/merged.json'),
    ('firebase/crosspong.rules.fragment.json', 'Tests/MultiPongFirebase/rules/crosspong.fragment.json'),
]


def check_stage4(android, sources):
    """Rooms (5375378, 3f13c40, 1fc4bc2, 452d82c, 83b050d, 9adf1f1, bb8acda) against Android."""
    compared = 0
    # The Firebase rules mirror is Android's rules byte for byte (line endings aside), with the house-player final rule.
    for rel, ios in STAGE4_RULES:
        mine = (ROOT / ios).read_bytes().replace(b'\r\n', b'\n')
        check(mine == android_bytes(android, rel).replace(b'\r\n', b'\n'), f'{ios} differs from Android {rel} at {STAGE1_COMMIT[:7]}')
        compared += 1
    fragment = (ROOT / 'Tests/MultiPongFirebase/rules/crosspong.fragment.json').read_text(encoding='utf-8')
    # generate-rules.cjs: friendly ? all(allBots, `$match.endsWith('_D')`, `${v(S,'host')} == auth.uid`, `${phase} == 'WAITING'`)
    house_final = ("$match.endsWith('_D')) && (newData.parent().parent().child('host').val() == auth.uid) && "
                   "(newData.child('phase').val() == 'WAITING')")
    check(house_final in fragment and house_final in (ROOT / 'Tests/MultiPongFirebase/rules/merged.json').read_text(encoding='utf-8'),
          'the rules mirror lacks the friendly host\'s house-only final (1fc4bc2)')
    tests = (ROOT / 'Tests/MultiPongFirebase/tests/crosspong.test.cjs').read_text(encoding='utf-8').replace('\r\n', '\n')
    android_tests = android_blob(android, 'firebase/tests/crosspong.test.cjs')
    start = android_tests.find("test('multi21 rematch creates host room before restoring bot seats'")
    check(start > 0 and tests.endswith(android_tests[start:]), 'crosspong.test.cjs lacks Android\'s multi21 rules tests (1fc4bc2)')
    compared += 1
    # The catalog: "Loading…" right after "Opening…" (3f13c40) and the novemberSeven2026 group (452d82c), Android's texts.
    app_text = android_rows(android_blob(android, APP_TEXT))
    catalog = swift_rows(CATALOG.read_text(encoding='utf-8'))
    for key, before in (('Loading…', 'Opening…'),):
        expected = [r for r in app_text if r[1] == key]
        mine = [r for r in catalog if r[1] == key]
        check(len(expected) == 1 and [r[2] for r in mine] == [expected[0][2]], f'the catalog row {key!r} differs from Android')
        keys = [r[1] for r in catalog]
        check(key in keys and before in keys and keys.index(key) == keys.index(before) + 1, f'the catalog row {key!r} does not follow {before!r}')
        compared += 1
    expected_rows = [r for r in app_text if r[0] == 'novemberSeven2026']
    mine_rows = [r for r in catalog if r[0] == 'novemberSeven2026']
    check(len(expected_rows) == 4 and mine_rows == expected_rows, 'the catalog rows novemberSeven2026 differ from the Android AppText.kt')
    compared += len(expected_rows)
    # Android's texts (EN/HE) at the iOS call sites.
    play = android_blob(android, KT + 'multiplayer/PlayActivity.kt')
    match_activity = android_blob(android, KT + 'multiplayer/PrivateMatchActivity.kt')
    exit_dialog = play[play.index('private fun confirmRoomExit'):play.index('private fun saveRoomAndExit')]
    texts = set(kotlin_pairs(exit_dialog)) | set(kotlin_pairs(exit_dialog, r'\baction\('))
    check(len(texts) == 7, f'Android confirmRoomExit texts changed: {sorted(texts)}')
    for name in ('Play again', 'Loading…'):
        texts |= {p for p in kotlin_pairs(match_activity + play) if p[0] == name}
    texts |= {p for p in kotlin_pairs(play) if p[0] in ('You sit nearest the camera. The other seats go clockwise.', 'Two players use the classic table.')}
    check(len(texts) == 11, f'the stage-4 texts changed: {sorted(texts)}')
    for en, he in sorted(texts):
        check(has_pair(sources, en, he), f'MultiPong lacks the Android text {en[:50]!r}')
    compared += len(texts)
    journey = android_blob(android, KT + 'cross/CrossJourneyActivity.kt')
    models = android_blob(android, KT + 'multiplayer/PongModels.kt')
    repository = android_blob(android, KT + 'multiplayer/PongRepository.kt')
    book = android_blob(android, KT + 'multiplayer/RoomBook.kt')
    rematch = android_blob(android, KT + 'multiplayer/FriendlyRematch.kt')
    rollback = android_blob(android, KT + 'multiplayer/SavedLobbyRollback.kt')
    comparison = android_blob(android, KT + 'multiplayer/SaveComparison.kt')
    ios_models = read('MultiPong/MPMultiplayerModels.swift')
    ios_controller = read('MultiPong/MPController.swift')
    ios_view = read('MultiPong/ModernPongView.swift')
    ios_rooms = read('MultiPong/ModernPongRooms.swift')
    ios_preferences = read('MultiPong/MPPreferences.swift')
    ios_repository = read('MultiPong/MPRepository.swift')
    ios_journey = read('MultiPong/MPXJourney.swift')
    rules = [
        # 5375378 / 1fc4bc2: rematches.
        (rematch, 'fun available(s:Session,uid:String)=s.kind==SessionKind.FRIENDLY && s.complete &&', ios_models,
         's.kind == .friendly && s.complete && s.participants[uid] != nil && s.participants[uid]?.bot == nil &&'),
        (rematch, 's.participants.values.all{it.id==uid || it.bot!=null}', ios_models, 's.participants.values.allSatisfy { $0.id == uid || $0.bot != nil }'),
        (rematch, 'return s.copy(code=code,host=uid,matches=emptyMap(),connections=emptyMap(),state="WAITING",', ios_models,
         'next.code = code; next.host = uid; next.matches = [:]; next.connections = [:]; next.state = "WAITING"'),
        (rematch, 'createdAt=now,lastActivityAt=now,departed=emptySet(),rounds=emptyMap())', ios_models,
         'next.createdAt = now; next.lastActivityAt = now; next.departed = [:]; next.rounds = [:]'),
        (play, 'val hostOnly=fresh.copy(participants=fresh.participants.filterKeys{it==repo.uid},seats=fresh.seats.filterKeys{it==repo.uid})', ios_controller,
         'hostOnly.participants = fresh.participants.filter { $0.key == uid }'),
        (play, 'repo.mutate(created.kind,created.code,{it.copy(participants=fresh.participants,seats=fresh.seats)})', ios_controller,
         'next.participants = fresh.participants; next.seats = fresh.seats'),
        (match_activity, 'if(again)MatchResultDialog.Action(tr("Play again","לשחק שוב"),0xff83dfad.toInt()){closeResult(true)}', ios_view,
         'MPXResultCard.Action(title: t("Play again", "לשחק שוב"), color: 0xff83dfad, close: { model.closeResult(replay: true) })'),
        (match_activity, 'else MatchResultDialog.Action(action,0xffa6dcff.toInt()){closeResult()}', ios_view,
         'MPXResultCard.Action(title: close, color: 0xffa6dcff, close: { model.closeResult() })'),
        (match_activity, 'secondary=if(again)MatchResultDialog.Action(action){closeResult()}else null', ios_view,
         'secondary: again ? MPXResultCard.Action(title: close, close: { model.closeResult() }) : nil'),
        # 5375378: the Loading page (iOS 2026-11-10: not while this player's own Ready is still needed, check_ios_fixes).
        (play, 'if(s.kind==SessionKind.FRIENDLY && s.participants.values.any{it.bot!=null})showMatchLoading()', ios_controller,
         'if s.kind == .friendly && s.participants.values.contains(where: { $0.bot != nil }),'),
        (play, 'private fun detach(){launchingMatch=false;roomEpoch++;fullRosterSeenAt=0L;rosterStartPosted=false;', ios_controller,
         'loadingMatch = false; roomEpoch &+= 1; fullRosterSeenAt = 0; rosterStartPosted = false'),
        # 1fc4bc2: saved friendly lineups, the full-roster pause and clockwise seats.
        (play, 'if(s.kind!=SessionKind.FRIENDLY||s.host!=repository?.uid||s.participants.values.count{it.bot==null}!=1)return', ios_controller,
         'guard s.kind == .friendly, s.host == repo.uid, s.participants.values.filter({ $0.bot == nil }).count == 1'),
        (play, 'seats.entries.firstOrNull{it.value==(s.tableSize-n)%s.tableSize}?.key?.let{s.participants[it]?.bot?.characterId}}', ios_controller,
         'let seat = (s.tableSize - n) % s.tableSize'),
        (play, 'prefs.getString("friendlyRoster${s.tableSize}","").orEmpty().split(",").mapNotNull(BotRoster::find).distinctBy{it.id}.take(s.tableSize-1)', ios_controller,
         'let players = Array(saved.prefix(max(0, s.tableSize - 1)))'),
        (play, 'PongRules.addFriendlyHousePlayer(next,repo.uid,participant(c),(s.tableSize-i-1)%s.tableSize)', ios_controller,
         'seat: (size - i - 1) % size)'),
        (play, 'if(s.tableSize>=3 && (fullRosterSeenAt==0L || android.os.SystemClock.uptimeMillis()-fullRosterSeenAt<700L))return', ios_controller,
         'if s.tableSize >= 3 && (fullRosterSeenAt == 0 || MPController.uptime - fullRosterSeenAt < 700) { return }'),
        (play, 'if(s.participants.size<s.capacity)fullRosterSeenAt=0L', ios_controller, 'if s.participants.count < s.capacity { fullRosterSeenAt = 0 }'),
        (play, '},700L)', ios_controller, 'try? await Task.sleep(nanoseconds: 700_000_000)'),
        (play, 'reviewRestoredRoster=false;fullRosterSeenAt=android.os.SystemClock.uptimeMillis()-700L;maybeStart(s)', ios_controller,
         'fullRosterSeenAt = MPController.uptime - 700'),
        (play, 'val seat=(s.tableSize-displaySeat)%s.tableSize', ios_rooms, '(tableSize - shown) % tableSize'),
        (play, 'if(repo.uid in s.participants && repo.uid!=s.host)row.addView', ios_rooms, 'if s.participants[model.userID] != nil && model.userID != s.host {'),
        (play, 'change {PongRules.addFriendlyHousePlayer(it,repo.uid,chosen,it.freeSeats().maxOrNull())}', ios_controller, 'let free = seat ?? room.freeSeats().max()'),
        (journey, 'val candidates=(saved+BotRoster.all.map{it.id}).filter{it!=avatar}.distinct().take(3)', ios_journey,
         'for id in saved + MPRoster.all.map({ $0.id }) where id != avatar && !candidates.contains(id) { candidates.append(id) }'),
        (journey, 'prefs.edit().putString("teamRoster${if(twoOpponents)4 else 3}",ids.drop(1).joinToString(",")).apply()', ios_journey,
         'preferences.setTeamRoster((two ?? twoOpponents) ? 4 : 3, ids.dropFirst().joined(separator: ","))'),
        (journey, 'setOnCheckedChangeListener{_,v->rememberTeamRoster();twoOpponents=v;restoreTeamRoster();teams()}', ios_journey,
         'rememberTeamRoster(twoOpponents: oldValue); restoreTeamRoster()'),
        # 83b050d / 9adf1f1: Back, explicit saves and the rollback.
        (play, 'val changed=if(local!=null)local.hasUnsavedChanges(current) else previous==null||!SaveComparison.same(previous,current)||playedSinceRoomOpen', ios_controller,
         'else if let previous { changed = !MPSaveComparison.same(previous, s) || playedSinceRoomOpen }'),
        (play, 'if(previous!=null&&!changed)leaveRoomScreen()else confirmRoomExit(current)', ios_controller,
         'if previous != nil && !changed { leaveRoomScreen() } else { confirmRoomExit(s) }'),
        (play, 'if(useOnline&&!SavedLobbyRollback.available(previous,s,repository!!.uid))', ios_controller,
         'online && !MPSavedLobbyRollback.available(previous, s, uid: repo.uid) ? .keepsEarlierEntry : .discardsChanges'),
        (play, 'action("Save and exit","שמירה ויציאה",0xff83dfad.toInt(),"room-save-exit")', ios_view,
         'action(t("Save and exit", "שמירה ויציאה"), color: FamilyKit.color(0xff83dfad)) { model.roomExitSave() }'),
        (play, 'action("Exit without saving","יציאה ללא שמירה",pink,"room-discard-exit")', ios_view,
         'action(t("Exit without saving", "יציאה ללא שמירה"), color: MPStyle.pink) { model.roomExitDiscard() }.foregroundStyle(.white)'),
        (play, 'action("Stay","להישאר",blue,"room-stay"){}', ios_view, 'action(t("Stay", "להישאר"), color: MPStyle.blue) { model.roomExitStay() }'),
        (play, 'if(!foreground||exiting||roomExitDialog?.isShowing==true||roomCode!=s.code)return', ios_controller,
         'guard foreground, !closing, !exiting, roomExitPrompt == nil, route == .lobby, session?.id == s.id else { return }'),
        (play, 'if(!delete){saveRoomAndExit(s);return}', ios_controller, 'func saveForLater() {\n        guard let s = session else { return }\n        saveRoomAndExit(s)'),
        (play, 'SavedLobbyRollback.available(previous,s,repo.uid)->repo.mutate(s.kind,s.code,', ios_controller,
         'restored = try await self.repo.mutate(s.kind, s.code) { try MPSavedLobbyRollback.restore(previous, edited: s, latest: $0, uid: uid) }'),
        (play, 'else->complete(Result.success(previous))', ios_controller, '} else { restored = previous }'),
        (play, 'val finished=room?.takeIf {it.complete&&!book.hasExplicitSave(SavedRoom(useOnline,it.kind,it.code))}', ios_controller,
         'let finished = session.flatMap { $0.complete && !preferences.hasExplicitSave($0) ? $0 : nil }'),
        (play, 'if(s.complete&&!book.hasExplicitSave(r)){book.dismissResult(r);local.remove(s);return@forEach}', ios_repository,
         'for s in sessions.values where s.complete && !keepCompleted(s) { remove(s) }'),
        (book, 'if(s.complete&&!hasExplicitSave(r)){store.edit().putBoolean("completed/${r.key}",true).apply();forget(r);return}', ios_preferences,
         'if s.complete && !hasExplicitSave(s) { flag("completed", s.id); removed(s); return }'),
        (book, '.putBoolean("completed/${r.key}",false).commit()) { "Could not save the game." }', ios_preferences, 'unflag("completed", s.id)'),
        (book, 'if(!r.online)local.saveCheckpoint(s)', ios_preferences, 'if let local { try? local.saveCheckpoint(room) }'),
        (repository, '"session" to PongCodec.session(s.copy(connections=emptyMap())),', ios_repository, 'room.connections = [:]'),
        (repository, 'copy(connections=emptyMap(),lastActivityAt=System.currentTimeMillis())', ios_repository,
         'restored.connections = [:]\n        restored.lastActivityAt = MPClock.now'),
        (repository, 'require(restored.kind==s.kind&&restored.code==s.code&&restored.host==uid)', ios_repository,
         'guard restored.kind == s.kind, restored.code == s.code, restored.host == uid else { throw MPError.permission }'),
        (repository, '((current?.matches?.keys?:emptySet())+s.matches.keys+restored.matches.keys).forEach {edit.remove("live/$it")}', ios_repository,
         'var ids = Set(s.matches.keys).union(restored.matches.keys)'),
        (comparison, 'private val housekeeping=setOf("connections","lastActivityAt","revision","serverAt","clientAt")', ios_models,
         'static let housekeeping: Set<String> = ["connections", "lastActivityAt", "revision", "serverAt", "clientAt"]'),
        (comparison, 'is Number->value.toDouble()', ios_models, 'return number.doubleValue'),
        (rollback, 'saved.state=="WAITING"&&current.state=="WAITING"&&saved.matches.isEmpty()&&current.matches.isEmpty()', ios_models,
         'saved.state == "WAITING" && current.state == "WAITING" && saved.matches.isEmpty && current.matches.isEmpty'),
        (rollback, 'require(latestBots==editedBots)', ios_models, 'guard latestBots == editedBots else { throw MPError.rollbackPeerEdit }'),
        (rollback, 'require(people.size<=latest.capacity)', ios_models, 'guard people.count <= latest.capacity else { throw MPError.rollbackFull }'),
        (rollback, 'if(latest.kind==SessionKind.TOURNAMENT)return restored', ios_models, 'if latest.kind == .tournament { return restored }'),
        (rollback, 'require(old !in seats.values)', ios_models, 'guard !seats.values.contains(old) else { throw MPError.rollbackSeat }'),
        # bb8acda: two-player tournaments stay pairs.
        (models, 'val table=if(!friendly&&capacity==2)2 else GroupTournament.tableSize(tableSize)', ios_models,
         'let table = !friendly && capacity == 2 ? 2 : MPGroupTournament.tableSize(tableSize)'),
        (play, 'if(twoPlayers&&table.selectedItemPosition!=0)table.setSelection(0,false)', ios_view, 'guard tournamentTwoPlayers, tournamentTable != 2 else { return }'),
        (play, 'robinHelp?.visibility=if(pairs())View.GONE else View.VISIBLE', ios_view, 'if table != 2 {'),
    ]
    for kotlin_source, kotlin, swift_source, swift in rules:
        check(kotlin in kotlin_source, f'Android changed: {kotlin[:70]}')
        check(swift in swift_source, f'iOS lacks the Android rule: {swift[:70]}')
    # The superseded behaviour is gone: Back no longer keeps a tournament silently, the old tournament question is gone.
    for old, source, label in [('tournamentExitPrompt', ios_controller + ios_view, 'the old "Save this tournament?" question'),
                               ('room.freeSeats().first', ios_controller, 'Add house player on the lowest free seat'),
                               ('primary: .init(title: close, color: MPXResultCard.pink)', ios_view, 'the pink-only result action')]:
        check(old not in source, f'MultiPong/ still has {label}')
    return compared + len(rules)


# ---- Stage 5 (2026-11-10): guidance and polish, checked against Android STAGE1_COMMIT (dd94c09) --------------------------

def ios_only_rows(text):
    """[(key, [es, ar, hi, nl])] of MultiPong/MPTextIOS.swift (rows may wrap over several lines)."""
    rows, i = [], 0
    while True:
        i = text.find('\n        ("', i)
        if i < 0:
            return rows
        key, i = parse_swift_string(text, i + 10)
        m = re.compile(r',\s*\[\s*').match(text, i)
        if not m:
            raise ValueError('unexpected MPTextIOS row near ' + key[:40])
        i, values = m.end(), []
        while True:
            value, i = parse_swift_string(text, i)
            values.append(value)
            m = re.compile(r',\s*').match(text, i)
            if m and text[m.end()] == '"':
                i = m.end()
                continue
            break
        m = re.compile(r'\s*\]\)').match(text, i)
        if not m:
            raise ValueError('unexpected MPTextIOS row end near ' + key[:40])
        i = m.end()
        rows.append((key, values))


def kotlin_template(text, start):
    """The raw Kotlin string (templates kept) that starts with `start`, as written between its quotes."""
    i = text.index('"' + start) + 1
    j = i
    while text[j] != '"' or text[j - 1] == BACKSLASH:
        j += 1
    return text[i:j]


def check_stage5(android, sources):
    """Guidance and polish (c93e760, 971e958, d0bed3b, a6c0b9a, d376d64, 80fc74e, 5375378, 63466d8, a7b47a4, e7f3f27, b58f0d5,
    651245f, 6fcb446, 1fc4bc2, dd94c09) against Android."""
    compared = 0
    app_text = android_rows(android_blob(android, APP_TEXT))
    catalog = swift_rows(CATALOG.read_text(encoding='utf-8'))
    # The catalog groups of this stage, and the rows it changed or added inside older groups.
    for group, count in (('dailyGuide2026', 17), ('courtTap2026', 4)):
        expected = [r for r in app_text if r[0] == group]
        mine = [r for r in catalog if r[0] == group]
        check(len(expected) == count and mine == expected, f'the catalog rows {group} differ from the Android AppText.kt')
        compared += len(expected)
    for key in ('Tap the golden court to serve there. The ball must bounce on your court first, then on the highlighted side.',
                'Swipe up through the bounced ball to smash', 'Your teammate is setting for you. Wait for the bounce.'):
        check([r for r in catalog if r[1] == key] == [r for r in app_text if r[1] == key] and any(r[1] == key for r in catalog),
              f'the catalog row {key[:50]!r} differs from Android')
        compared += 1
    # R.string.tap_marked_court (d376d64 English) and tap_opponent_side_to_serve in six languages.
    issue = journey_texts(read('MultiPong/MPText.swift'), 'issueTexts')
    for name in ('tap_marked_court', 'tap_opponent_side_to_serve'):
        english = android_strings(android_blob(android, ISSUE.format(''))).get(name)
        check(english is not None and swift_literal(english) in sources, f'R.string.{name} is not shown')
        for lang, folder in FOLDERS.items():
            local = android_strings(android_blob(android, ISSUE.format(folder))).get(name)
            check(local is not None and issue.get((english, lang)) == local, f'{name} ({lang}): Android {local!r}, MPText {issue.get((english, lang))!r}')
            compared += 1
    # Android's texts (EN/HE) at the iOS call sites.
    guide = android_blob(android, KT + 'cross/CrossPracticeGuide.kt')
    text_kt = android_blob(android, KT + 'cross/CrossText.kt')
    activity = android_blob(android, KT + 'cross/CrossActivity.kt')
    tutorial = android_blob(android, KT + 'cross/CrossTutorial.kt')
    journey = android_blob(android, KT + 'cross/CrossJourneyActivity.kt')
    texts = set(kotlin_pairs(guide, r'AppText\.t\('))
    check(len(texts) == 17, f'Android CrossPracticeGuide texts changed: {len(texts)}')
    texts |= {p for p in kotlin_pairs(text_kt, r'AppText\.t\(') if p[0] in ('Swipe up through the bounced ball to smash', 'Your teammate is setting for you. Wait for the bounce.')}
    texts |= {p for p in kotlin_pairs(activity) if p[0].startswith('Serve: tap another player’s court')}
    texts |= {p for p in kotlin_pairs(tutorial) if p[0].startswith('When the ball reaches your paddle, tap the other player’s court')}
    texts |= {p for p in kotlin_pairs(journey) if p[0] == 'Controls: '}
    check(len(texts) == 23, f'the stage-5 Android texts changed: {len(texts)}')
    for en, he in sorted(texts):
        check(has_pair(sources, en, he), f'MultiPong lacks the Android text {en[:60]!r}')
    compared += len(texts)
    # d0bed3b: the serve card's court-tap template (who / where become iOS who / side).
    serve = [kotlin_template(tutorial, "Tap ${who(lesson.expected)}'s side"), kotlin_template(tutorial, 'הקישו בצד של ${who')]
    swift = [s.replace('${who(lesson.expected)}', '\\(who(lesson.expected))').replace('${where(lesson.expected, false)}', '\\(side(lesson.expected, false))')
              .replace('${where(lesson.expected, true)}', '\\(side(lesson.expected, true))') for s in serve]
    check('"' + swift[0] + '",' in sources and '"' + swift[1] + '")' in sources, 'MultiPong lacks the d0bed3b serve card text')
    compared += 2
    ios_text = read('MultiPong/CrossText.swift')
    ios_journey = read('MultiPong/MPXJourney.swift')
    ios_teams = read('MultiPong/MPXTeams.swift')
    ios_tutorial = read('MultiPong/CrossTutorial.swift')
    ios_controller = read('MultiPong/MPController.swift')
    ios_rooms = read('MultiPong/ModernPongRooms.swift')
    ios_view = read('MultiPong/ModernPongView.swift')
    ios_ui = read('MultiPong/MPXUI.swift')
    ios_result = read('MultiPong/MPXResult.swift')
    ios_feedback = read('MultiPong/CrossScoreFeedback.swift')
    ios_scene = read('MultiPong/CrossScene.swift')
    ios_guide = read('MultiPong/CrossPracticeGuide.swift')
    ios_engine = read('MultiPong/CrossEngine.swift')
    teams_kt = android_blob(android, KT + 'cross/CrossOnlineTeamsActivity.kt')
    match_kt = android_blob(android, KT + 'multiplayer/PrivateMatchActivity.kt')
    play = android_blob(android, KT + 'multiplayer/PlayActivity.kt')
    card_kt = android_blob(android, KT + 'TournamentTableCard.kt')
    result_kt = android_blob(android, KT + 'MatchResultDialog.kt')
    feedback_kt = android_blob(android, KT + 'cross/CrossScoreFeedback.kt')
    court_kt = android_blob(android, KT + 'cross/CrossCourt.kt')
    dialog_kt = android_blob(android, KT + 'GuideDialog.kt')
    layout_kt = android_blob(android, KT + 'MatchSceneLayout.kt')
    spacing_kt = android_blob(android, KT + 'PongSpacing.kt')
    button_kt = android_blob(android, KT + 'PongButton.kt')
    reception_kt = android_blob(android, KT + 'ReceptionCamera.kt')
    rules = [
        # c93e760: CrossPracticeGuide.instruction / tip.
        (guide, 'CrossSkill.RETURN,CrossSkill.DEFEND->t0(he)+"\\n\\n"+t1(he)', ios_guide, 'case .returning, .defend: return t0(he) + "\\n\\n" + t1(he)'),
        (guide, 'CrossSkill.BACKHAND->t2(he)+"\\n\\n"+t5(he)+" "+t3(he)', ios_guide, 'case .backhand: return t2(he) + "\\n\\n" + t5(he) + " " + t3(he)'),
        (guide, 'CrossSkill.SHAPE->t4(he)+"\\n\\n"+t2(he)+" "+t3(he)', ios_guide, 'case .shape: return t4(he) + "\\n\\n" + t2(he) + " " + t3(he)'),
        (guide, 'p.stage.aimed->if(p.engine.selectedAim==null)t12(he)else t13(he)', ios_guide, 'if p.stage.aimed { return p.engine.selectedAim == nil ? t12(he) : t13(he) }'),
        (guide, 'p.stage.skill==CrossSkill.SET->CrossText.setTip(p.engine,he)?:t14(he)', ios_guide, 'case .set: return CrossText.setTip(p.engine, he) ?? t14(he)'),
        # c93e760 / 651245f / 971e958 / d376d64: the journey's brief, HUD and Help.
        (journey, 'private fun controls()=tr("Controls: ","רמת השליטה: ")+ControlChoice.title(CrossControl.BEGINNER.choice,hebrew)', ios_journey,
         'tr("Controls: ", "רמת השליטה: ") + MPControlChoice.title(CrossControl.beginner.choice, hebrew: hebrew)'),
        (journey, 'text(body,controls(),16f,true)', ios_journey, 'text(model.controls(), 16, bold: true)'),
        (journey, 'controls()+"\\n\\n"+instruction(stage)', ios_journey, 'help = controls() + "\\n\\n" + instruction(stage)'),
        (journey, '"\\u2066${p.successes}\\u00a0/\\u00a0${p.goal}\\u2069 · ♥ ${3-p.mistakes}"', ios_journey,
         '"\\u{2066}\\(p.successes)\\u{00a0}/\\u{00a0}\\(p.goal)\\u{2069} · ♥ \\(3 - p.mistakes)"'),
        (journey, 'else "\\u2066${p.successes}\\u00a0/\\u00a0${p.goal}\\u2069",22f,true)', ios_journey, 'score = "\\u{2066}\\(p.successes)\\u{00a0}/\\u{00a0}\\(p.goal)\\u{2069}"'),
        (journey, 'else if(e.receivingSet)CrossText.receivingSetTip(e,hebrew)else if(e.referee.mayServe(0))getString(R.string.tap_opponent_side_to_serve)else if(p!=null)CrossPracticeGuide.tip(p,hebrew)',
         ios_journey, 'else if e.receivingSet { tip = CrossText.receivingSetTip(e, hebrew) }'),
        (journey, 'getString(R.string.tap_opponent_side_to_serve)', ios_journey, 'else if e.referee.mayServe(0) { tip = MPText.issue("Tap an opponent’s side to serve") }'),
        (journey, 'else if(p!=null)CrossPracticeGuide.tip(p,hebrew)else CrossText.setTip(e,hebrew)', ios_journey, 'else if let p { tip = CrossPracticeGuide.tip(p, hebrew) }'),
        (journey, '"$title\\n${controls()} · \\u2066$score\\u2069\\n$tip"', ios_journey, 'controls() + " · \\u{2066}" + score + "\\u{2069}"'),
        (journey, 'fixedPortraitStatusLines=if(practice==null)3 else 4', ios_journey, 'var hudLines: Int { practice == nil ? 3 : 4 }'),
        (journey, 'override fun updateDrawState(paint:android.text.TextPaint){paint.baselineShift-=dp(4)}', ios_journey, '.offset(y: model.hudScore == nil ? -4 : 0)'),
        (journey, 'AlignmentSpan.Standard(android.text.Layout.Alignment.ALIGN_CENTER),0,line.lastIndexOf(\'\\n\')+1', ios_journey,
         'Text(model.hudTip).multilineTextAlignment(.leading)'),
        (layout_kt, 'if(fixedPortraitStatusLines!=null)minLines=if(wide)1 else fixedPortraitStatusLines', ios_journey,
         '.frame(maxWidth: .infinity, minHeight: wide ? nil : fixed, maxHeight: wide ? nil : fixed)'),
        # 971e958: receivingSetTip on the team courts too.
        (text_kt, 'return if(e.referee.phase==RallyPhase.RECEIVABLE)', ios_text, 'if e.referee.phase == .receivable {'),
        (teams_kt, 'g.receivingSet->CrossText.receivingSetTip(g,he)', ios_teams, 'else if game.receivingSet { next = CrossText.receivingSetTip(game, hebrew) }'),
        # d0bed3b: tutorial navigation.
        (tutorial, 'val canGoNext get() = index < lessons.lastIndex', ios_tutorial, 'var canGoNext: Bool { index < lessons.count - 1 }'),
        (activity, 'if(g.canGoBack)actions += back', ios_rooms, 'back: tourCard.canGoBack ?'),
        (activity, 'if(g.canGoNext)actions += next', ios_rooms, 'next: tourCard.canGoNext ?'),
        (activity, 'else prefs.edit().putBoolean("guide_seen",true).apply()', ios_controller, 'if !t.canGoNext { preferences.crossGuideSeen = true }'),
        (activity, 'GuideAction(R.string.guide_next, 0xff58bd8c.toInt()) { if (g.next()) showGuideCard() }', ios_controller, 'if t.next() { showTourCard() }\n    }'),
        (activity, 'val blue = 0xffb8d9ff.toInt()', ios_ui, 'static let blueFill = Color(red: 0xb8 / 255, green: 0xd9 / 255, blue: 1)'),
        (activity, 'GuideAction(R.string.guide_next, 0xff58bd8c.toInt())', ios_ui, 'static let nextFill = Color(red: 0x58 / 255, green: 0xbd / 255, blue: 0x8c / 255)'),
        (activity, 'actions += GuideAction(R.string.guide_show,blue)', ios_rooms, 'MPXGuideAction(title: t("Show me", "הראו לי"), fill: MPXGuideStyle.blueFill)'),
        (activity, 'if(g!=null){if(g.canGoBack){g.back();showGuideCard()}else finish()}', ios_controller, 'if tourCard == nil && t.canGoBack { t.back(); showTourCard() } else { exitLearning() }'),
        (dialog_kt, 'if(buttons.childCount>0)body.addView(buttons,LinearLayout.LayoutParams(-1,-2).apply { topMargin=dp(PongSpacing.ACTION_TOP_DP) })', ios_ui,
         '}.padding(.top, MPSpacing.actionTop)\n            }'),
        # 5375378: the local match's green Play again.
        (activity, 'MatchResultDialog.Action(tr("Play again","לשחק שוב"),0xff83dfad.toInt()){restart()}', ios_rooms,
         'primary: .init(title: t("Play again", "לשחק שוב"), color: 0xff83dfad) { model.closeCrossResult(playAgain: true) }'),
        # 1fc4bc2: status lines from the reading edge (the classic court's stays centred, b0cdeb3).
        (activity, 'gravity = Gravity.START or Gravity.CENTER_VERTICAL; textDirection=', ios_rooms, '.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)'),
        (match_kt, 'status=label("",16f,true).apply {outlined=true;setTextColor(Color.WHITE);gravity=Gravity.START or Gravity.CENTER_VERTICAL;', ios_rooms,
         'Text(text).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.leading)'),
        (match_kt, 'status=label("",16f,true).apply {outlined=true;setTextColor(Color.WHITE);gravity=Gravity.CENTER;', ios_view,
         'Text(gameStatus).font(.callout.bold()).multilineTextAlignment(.center)'),
        (teams_kt, 'hint=label("",15f,true).apply{setTextColor(Color.WHITE);gravity=Gravity.START or Gravity.CENTER_VERTICAL;', ios_teams,
         'Text(model.hint).font(.system(size: 15, weight: .bold)).multilineTextAlignment(.leading)'),
        # d376d64 / 80fc74e: the steady point highlight.
        (feedback_kt, 'const val HOLD=2150L;const val DURATION=2750L', ios_feedback, 'static let hold = 2150\n    static let duration = 2750'),
        (feedback_kt, 'val alpha=if(age<HOLD)255 else ((DURATION-age)*255/(DURATION-HOLD)).toInt()', ios_feedback,
         'return (CrossScoreFeedback.duration - age) * 255 / (CrossScoreFeedback.duration - CrossScoreFeedback.hold)'),
        # dd94c09: the team scoreboard's 4 dp bottom padding.
        (court_kt, 'canvas.drawRoundRect(x,y,x+w,y+h+bottomPadding,12*density,12*density,paint)', ios_scene,
         'CGRect(x: x, y: height - (y + h + bottomPadding), width: max(1, w), height: h + bottomPadding)'),
        (court_kt, 'val bottomPadding=4*density', ios_scene, 'let bottomPadding = 4.0'),
        # d376d64 / b58f0d5 / 6fcb446: the result card.
        (result_kt, 'val colors = intArrayOf(gold, 0xff183e62.toInt(), 0xff104c3b.toInt(), 0xff632d50.toInt())', ios_result,
         'static let accents: [UInt32] = [0xff5b450d, 0xff183e62, 0xff104c3b, 0xff632d50]'),
        (result_kt, 'val gold = 0xff5b450d.toInt()', ios_result, 'static let gold: UInt32 = 0xff5b450d'),
        (result_kt, 'calculateContrast(c,0xff808080.toInt())<4.5)', ios_result, 'for _ in 0..<12 where contrast(c, 0xff808080) < 4.5 { c = blendBlack(c, 0.15) }'),
        (result_kt, 'c=androidx.core.graphics.ColorUtils.blendARGB(c,Color.BLACK,.15f)}', ios_result, 'channel(24, 255) << 24 | channel(16, 0) << 16 | channel(8, 0) << 8 | channel(0, 0)'),
        (result_kt, 'intArrayOf(0x80ffffff.toInt(), 0x80ffffff.toInt())', ios_result, '.fill(FamilyKit.color(0x80ffffff))'),
        (result_kt, 'readable(0xffff5ba6.toInt()), true).apply {\n            outlined=false', ios_result, 'color: FamilyKit.color(Self.readable(0xffff5ba6))'),
        (result_kt, 'readable(result.color?:0xff142c42.toInt())', ios_result, 'FamilyKit.color(Self.readable(row.color ?? Self.ink))'),
        (result_kt, 'setShadowLayer(0f, 0f, 0f, Color.TRANSPARENT)', ios_result, '/// Android d376d64: solid lettering without a shadow.'),
        (result_kt, 'panel.addView(actions,LinearLayout.LayoutParams(-1,-2).apply { topMargin=dp(PongSpacing.ACTION_TOP_DP) })', ios_result,
         '.padding(.top, MPSpacing.actionTop)\n        }'),
        # a6c0b9a: tournament tables.
        (play, 'val outer=card(color=blue).apply{tag="tournament-round"}', ios_rooms, 'return card(MPStyle.blue) {'),
        (play, 'inner.addView(TournamentTableCard(this,s,m,through,hebrew,repository!!.uid)', ios_rooms, 'MPXTournamentTable(session: s, match: m, through: through, hebrew: he, localId: model.userID)'),
        (play, '(inner.getChildAt(i).layoutParams as LinearLayout.LayoutParams).apply{topMargin=dp(8);bottomMargin=dp(8)}', ios_rooms,
         'let above: CGFloat = inTable ? 8 - gap : MPSpacing.actionTop - 8'),
        (card_kt, 'if(id==localId)box.addView(TextView(context).apply{text=AppText.t("You","אתם",he);textSize=13f', ios_rooms,
         'Text(MPText.t("You", "אתם", hebrew)).font(.system(size: 13))'),
        # 63466d8 / a7b47a4 / d376d64 / e7f3f27 / b58f0d5: spacing.
        (spacing_kt, 'const val ACTION_TOP_DP = 16', ios_view, 'static let actionTop: CGFloat = 16'),
        (play, 'parent.addView(this,LinearLayout.LayoutParams(-1,-2).apply {setMargins(0,dp(com.appsbybros.minik.pingpong.PongSpacing.ACTION_TOP_DP),0,dp(12))})',
         ios_rooms, '.foregroundStyle(.white).padding(.top, MPSpacing.actionTop)'),
        (play, '(layoutParams as LinearLayout.LayoutParams).apply{topMargin=dp(com.appsbybros.minik.pingpong.PongSpacing.ACTION_TOP_DP);bottomMargin=dp(18)}', ios_rooms,
         '.padding(.top, m.phase == .playing ? MPSpacing.actionTop - 8 : 0).padding(.bottom, m.phase == .playing ? 18 : 0)'),
        (play, '(saveProfile.layoutParams as LinearLayout.LayoutParams).bottomMargin=dp(16)', ios_view,
         '.disabled(!model.connected).padding(.top, MPSpacing.actionTop - gap).padding(.bottom, 16 - gap)'),
        (play, 'box.addView(code,LinearLayout.LayoutParams(-1,-2).apply {topMargin=dp(12);bottomMargin=0})', ios_view, '.padding(.top, MPSpacing.actionTop - gap)\n        }'),
        (journey, 'body.addView(b,LinearLayout.LayoutParams(-1,-2).apply{topMargin=dp(PongSpacing.ACTION_TOP_DP)});return b}', ios_journey,
         '}.buttonStyle(.plain).padding(.top, MPSpacing.actionTop)'),
        (teams_kt, 'body.addView(b,LinearLayout.LayoutParams(-1,-2).apply{topMargin=dp(PongSpacing.ACTION_TOP_DP)});return b', ios_teams,
         '}.buttonStyle(.plain).padding(.top, MPSpacing.actionTop)'),
        (teams_kt, '(body.getChildAt(body.childCount-1).layoutParams as LinearLayout.LayoutParams).apply{topMargin=dp(32);bottomMargin=dp(16)}', ios_teams,
         '.padding(.top, 32 - MPSpacing.actionTop).padding(.bottom, 16)'),
        (reception_kt, '},LinearLayout.LayoutParams(-1,-2).apply { topMargin=(PongSpacing.ACTION_TOP_DP*d).toInt() })', ios_ui, '}.buttonStyle(.plain).padding(.top, MPSpacing.actionTop)'),
        # 6fcb446: word labels one size larger.
        (button_kt, 'super.setTextSize(unit,if(unit==android.util.TypedValue.COMPLEX_UNIT_SP && size in 10f..24f)size+1f else size)', ios_ui,
         'Text(item.title).font(.system(size: 17, weight: .bold))'),
        (button_kt, 'size+1f', ios_result, 'Text(action.title).font(.system(size: 19, weight: .bold))'),
        (button_kt, 'size+1f', ios_journey, 'Text(title).font(.system(size: 18, weight: .semibold))'),
        (button_kt, 'size+1f', ios_teams, 'Text(title).font(.system(size: 18, weight: .semibold))'),
        (reception_kt, 'textSize=18f;minHeight=(56*d).toInt()', ios_ui, '.font(.system(size: 19, weight: .semibold))'),
    ]
    for kotlin_source, kotlin, swift_source, swift in rules:
        check(kotlin in kotlin_source, f'Android changed: {kotlin[:70]}')
        check(swift in swift_source, f'iOS lacks the Android rule: {swift[:70]}')
    compared += len(rules)
    # Superseded texts and behaviour are gone.
    for old, source, label in [('"Tap the called court to serve"', ios_journey, 'the old serve tip'),
                               ('"Swipe now to smash!"', ios_journey + ios_teams, 'the old smash tip'),
                               ('func role(', ios_journey, 'the brief\'s partner/opponent line'),
                               ('Tap the golden island to aim', ios_journey, 'the old Daily instructions'),
                               ('"Tap the highlighted court to serve"', sources, 'the old tap_marked_court English'),
                               ('/ 220 % 2', ios_feedback, 'the 220 ms blinking highlight'),
                               ('Color(red: 133 / 255, green: 215 / 255, blue: 1)', ios_ui, 'the old light blue Next'),
                               ('Serve: tap your side, drag left or right to aim, then lift.', ios_controller, 'the old Beginner help'),
                               ('Tap when the ball reaches your paddle. Drag sideways to choose the player', ios_tutorial, 'the old Standard hint'),
                               ('.shadow(color: FamilyKit.color(0xaa091c37)', ios_result, 'the result lettering shadow'),
                               ('} else { endTour() }', ios_controller, 'Next ending the guide')]:
        check(old not in source, f'MultiPong/ still has {label}')
    # Owner decision (stage 5): texts of the stage-5 screens that Android leaves in English get iOS-only translations.
    ios_source = read('MultiPong/MPTextIOS.swift')
    ios_rows = ios_only_rows(ios_source)
    used = sources.replace(ios_source, '')
    android_keys = {r[1] for r in app_text}
    android_templates = [re.compile(r'\A' + '(.*?)'.join(re.escape(p) for p in re.split(r'\{\d+\}', k)) + r'\Z', re.S) for k in android_keys if '{0}' in k]
    outside_app_text = {'Ball hit the net'}  # Android's teamOutcome never passes it through AppText (no "{0} hit the net").
    # The stage-5 rows come first; the 2026-11-10 rows after them are checked by check_ios_fixes.
    check(len(ios_rows) >= 17 and len({k for k, _ in ios_rows}) == len(ios_rows), f'MPTextIOS rows changed: {len(ios_rows)}')
    for key, values in ios_rows[:STAGE5_IOS_ROWS]:
        check(key not in android_keys, f'MPTextIOS {key[:40]!r} is an Android catalog row (Android\'s translation must be used)')
        check(key in outside_app_text or not any(t.match(key) for t in android_templates), f'MPTextIOS {key[:40]!r} matches an Android catalog template')
        check(len(values) == 4 and all(v.strip() and v != key for v in values), f'MPTextIOS {key[:40]!r} is not translated into every language')
        check(all(placeholders(v) == placeholders(key) for v in values), f'MPTextIOS {key[:40]!r} has other placeholders')
        call = swift_literal(key)[:-1] if '{0}' not in key else '"' + key.split('{0}')[0]
        check(call in used, f'MPTextIOS {key[:40]!r} is not used')
        compared += 1
    check(len(ios_rows) >= STAGE5_IOS_ROWS and ios_rows[STAGE5_IOS_ROWS - 1][0] == 'Finish your current match before starting another.',
          'the stage-5 MPTextIOS rows are no longer the first 17')
    return compared


# ---- 2026-11-10: iOS-only fixes (owner decision): the 2-seat lineup, the host's Loading page, every text translated -----------

# MPTextIOS rows of stage 5 (check_stage5); the rows after them are the 2026-11-10 translations (check_ios_fixes).
STAGE5_IOS_ROWS = 17
IOS_FIX_ROWS = 85
# Keys that an Android `{0}` template would fill with English words, so iOS gives them an exact row read before the templates.
TEMPLATE_LEAKS = {'Ball hit the net', 'Fit all players', 'Playing now'}
# Texts of the Simple experience (ModernPongView's classic single-player menu, guide, help, settings and status; MPTutorial). The
# Multi Ping Pong app only opens the full experience (PingPongOnlyRootView), and Minik Math Plus uses Sources/ModernPong, so
# these texts never show; they stay as on Android.
SIMPLE_ONLY = {
    'MINIK Ping Pong', 'Good game!', 'Minik level', 'Start a new game', 'Continue game', 'Return and aim', 'Beginner, Standard and Pro',
    'Don’t show the guide automatically', 'Well done! The ball landed in the right area.',
    'Try again. Watch the timing and where the ball lands.',
    'Waiting for the other player to return…', 'Tap a point on the table to aim your serve', 'Swipe forward through the ball to serve',
    'The ball landed outside', 'Two bounces — point', 'The serve must bounce on both sides', 'Tap to return · Swipe diagonally to aim',
    'Beginner: move into place for an automatic hit; a small sideways swipe aims it. Opponent skill comes from your chosen house player.',
    'Pro: precise timing and power. Opponent skill comes from your chosen house player.',
    'Standard: tap or swipe; faster swipes add power. Opponent skill comes from your chosen house player.',
    'Beginner hits automatically when your paddle is in place. Easy, Medium and Hard use forgiving taps and diagonal swipes. Super hard requires precise swipes.',
    'Tap any point on the table to aim your serve. The first bounce is on your side; the second is on the opponent’s side.',
    'Tap when the ball reaches your paddle for a forgiving return that keeps its natural sideways direction. Swipe diagonally forward and left or right to choose the landing side, including a wide cross-table shot.',
    'Beginner is the default: move the paddle into the ball’s path and it hits automatically. Standard allows taps and forgiving diagonal swipes. Pro requires precise swipe timing, direction and power. House players have their own power, forehand, backhand and serve skills.',
}
# Deliberately English everywhere: the app's name (Android keeps "Multiplayer Ping Pong" in every catalog translation, e.g. "¡Juguemos
# a Multiplayer Ping Pong!") and the subject of the feedback e-mail the developers receive.
KEPT_ENGLISH = {'Multiplayer Ping Pong', 'Multiplayer Ping Pong feedback'}
# Files whose literals are not English interface texts: the catalogs and MPText's own tables, MPResultWords' six-language switch,
# the nickname words and house-player names (never translated), and the Simple experience's tutorial.
TEXT_FILES_SKIPPED = {'MPTextCatalog.swift', 'MPTextIOS.swift', 'MPText.swift', 'MPXResult.swift', 'MPPreferences.swift', 'MPRoster.swift',
                      'MPTutorial.swift'}
# Literals that are never shown: decoding errors (CrossStateError), MPError's raw values (PlayActivity.error shows its own
# explanations), CrossTeamRoom's failure keys (the team screen shows its own explanations), the family link (FamilyText).
NOT_SHOWN_BEFORE = re.compile(r'(CrossStateError\.invalid\(|\bcase \w+ = |static let (code|notFound|newer|started|full|restore|interrupted) = |'
                              r'FamilyMessages\.text\(|let note = |if MPText\.language == "en" \{ return )$')
# Android resource strings shown through MPText.issue / MPText.journey (their own six-language tables, compared with Android's
# issue_review.xml and journey.xml in --android mode).
RESOURCE_CALL_BEFORE = re.compile(r'MPText\.(issue|journey)\([^\n]*$')


def swift_literals(text):
    """(offset, value) of every Swift string literal outside comments; each interpolation becomes U+0001."""
    i, n = 0, len(text)
    while i < n:
        if text.startswith('//', i):
            j = text.find('\n', i)
            i = n if j < 0 else j
            continue
        if text.startswith('/*', i):
            j = text.find('*/', i)
            i = n if j < 0 else j + 2
            continue
        if text.startswith('"""', i):
            j = text.find('"""', i + 3)
            yield i, text[i + 3:j]
            i = j + 3
            continue
        if text[i] != '"':
            i += 1
            continue
        start, i, out = i, i + 1, []
        while text[i] != '"':
            c = text[i]
            if c != BACKSLASH:
                out.append(c)
                i += 1
                continue
            e = text[i + 1]
            if e == '(':
                depth, i = 1, i + 2
                while depth:
                    if text[i] == '(':
                        depth += 1
                    elif text[i] == ')':
                        depth -= 1
                    elif text[i] == '"':
                        i += 1
                        while text[i] != '"':
                            i += 2 if text[i] == BACKSLASH else 1
                    i += 1
                out.append('\x01')
            elif e == 'u':
                j = text.index('}', i)
                out.append(chr(int(text[i + 3:j], 16)))
                i = j + 1
            else:
                out.append({'n': '\n', 't': '\t', 'r': '\r', '0': '\0'}.get(e, e))
                i += 2
        yield start, ''.join(out)
        i += 1


def template_patterns(rows, longest_first):
    """[(key, regex)] of the `{n}` keys, in MPText.t order (Android: longest first, catalog order on ties)."""
    keyed = [(k, idx) for idx, k in enumerate(rows) if re.search(r'\{\d+\}', k)]
    if longest_first:
        keyed.sort(key=lambda item: (-len(item[0].encode('utf-16-le')) // 2, item[1]))
    return [(k, re.compile(r'\A' + '(.*?)'.join(re.escape(p) for p in re.split(r'\{\d+\}', k)) + r'\Z', re.S)) for k, _ in keyed]


def shown_translation(en, android, ios, android_templates, ios_templates):
    """How MPText.t shows `en` in a catalog language: 'android', 'ios', or None when it stays English or a template would fill it
    with English words of `en` itself (U+0001 marks the caller's interpolations)."""
    if en in android:
        return 'android'
    if en in ios:
        return 'ios'
    for templates, source in ((android_templates, 'android'), (ios_templates, 'ios')):
        for _, pattern in templates:
            m = pattern.match(en)
            if m:
                return None if any(re.search('[A-Za-z]', g.replace('\x01', '')) for g in m.groups()) else source
    trimmed = en.strip()
    if trimmed != en and trimmed in android:
        return 'android'
    if en.startswith(' · '):
        return shown_translation(en[3:], android, ios, android_templates, ios_templates)
    return None


def interface_text(value):
    """An English text a person reads: words with a space, a capitalised word, or "OK" (not keys, identifiers or asset names)."""
    if re.search('[֐-׿؀-ۿऀ-ॿ]', value) or not re.search('[A-Za-z]{2}', value):
        return False
    if ' ' in value.strip() and not re.fullmatch(r'[\w./:\-]+', value.strip()):
        return True
    return value == 'OK' or re.fullmatch(r'[A-Z][a-z]+[!?.…]?', value) is not None


def check_ios_fixes(android, sources):
    """The 2026-11-10 iOS-only fixes (owner decision): the 2-seat friendly never restores a lineup, the host is never kept behind
    the Loading page while their own Ready is needed, and no MultiPong text falls back to English in Spanish, Arabic, Hindi or
    Dutch (every interface literal resolves to an Android catalog row or an MPTextIOS row, and no call site writes English and
    Hebrew only)."""
    compared = 0
    app_text = android_rows(android_blob(android, APP_TEXT))
    catalog_rows = {r[1]: r[2] for r in app_text}
    ios_source = read('MultiPong/MPTextIOS.swift')
    ios_rows = ios_only_rows(ios_source)
    ios = dict(ios_rows)
    android_templates = template_patterns(list(catalog_rows), True)
    ios_templates = template_patterns([k for k, _ in ios_rows], False)
    used = sources.replace(ios_source, '')
    # The new MPTextIOS rows: not Android keys, not taken by an Android template (unless it would fill them with English), translated
    # into every language (Arabic in Arabic letters, Hindi in Devanagari, no bidi controls), placeholders kept, used in MultiPong.
    new_rows = ios_rows[STAGE5_IOS_ROWS:]
    check(len(new_rows) == IOS_FIX_ROWS, f'MPTextIOS 2026-11-10 rows changed: {len(new_rows)}')
    bidi = re.compile('[‎‏‪-‮⁦-⁩]')
    for key, values in new_rows:
        check(key not in catalog_rows, f'MPTextIOS {key[:40]!r} is an Android catalog row (Android\'s translation must be used)')
        taken = next((p for _, p in android_templates if p.match(key)), None)
        if key in TEMPLATE_LEAKS:
            check(taken is not None and shown_translation(key, catalog_rows, {}, android_templates, []) is None,
                  f'MPTextIOS {key[:40]!r} is listed as a template leak but no Android template fills it with English')
        else:
            check(taken is None, f'MPTextIOS {key[:40]!r} matches an Android catalog template')
        check(len(values) == 4 and all(v.strip() and v != key for v in values), f'MPTextIOS {key[:40]!r} is not translated into every language')
        check(all(placeholders(v) == placeholders(key) for v in values), f'MPTextIOS {key[:40]!r} has other placeholders')
        check(not any(bidi.search(v) for v in values), f'MPTextIOS {key[:40]!r} has a bidi control character')
        if len(values) == 4 and re.search('[A-Za-z]{2}', key):
            check(re.search('[؀-ۿ]', values[1]), f'MPTextIOS {key[:40]!r}: the Arabic text has no Arabic letters')
            check(re.search('[ऀ-ॿ]', values[2]), f'MPTextIOS {key[:40]!r}: the Hindi text is not in Devanagari')
        parts = [p for p in key.split('{0}') if p.strip()]
        check(all(swift_literal(p)[1:-1] in used for p in parts), f'MPTextIOS {key[:40]!r} is not used')
        compared += 1
    # No MultiPong interface text falls back to English: every English literal a person can read resolves to a row, unless it is
    # Simple-experience only or deliberately English (both listed above, and both still in the sources).
    seen_simple, seen_kept = set(), set()
    text_source = read('MultiPong/MPText.swift')
    for path in sorted((ROOT / 'MultiPong').glob('*.swift')):
        if path.name in TEXT_FILES_SKIPPED:
            continue
        text = path.read_text(encoding='utf-8')
        for offset, value in swift_literals(text):
            if not interface_text(value):
                continue
            before = text[max(0, offset - 80):offset]
            if NOT_SHOWN_BEFORE.search(before):
                continue
            # A literal on the line of an MPText.issue / journey call with its own six-language row; other literals of that line
            # (a tr(...) beside it) are checked like any text.
            if RESOURCE_CALL_BEFORE.search(before) and swift_literal(value) + ': [' in text_source:
                continue
            if value in SIMPLE_ONLY:
                seen_simple.add(value)
                continue
            if value in KEPT_ENGLISH:
                seen_kept.add(value)
                continue
            line = text.count('\n', 0, offset) + 1
            check(shown_translation(value, catalog_rows, ios, android_templates, ios_templates) is not None,
                  f'{path.name}:{line}: {value[:60]!r} stays English in Spanish, Arabic, Hindi and Dutch')
            compared += 1
    check(seen_simple == SIMPLE_ONLY, f'SIMPLE_ONLY lists texts no longer in MultiPong/: {sorted(SIMPLE_ONLY - seen_simple)}')
    check(seen_kept == KEPT_ENGLISH, f'KEPT_ENGLISH lists texts no longer in MultiPong/: {sorted(KEPT_ENGLISH - seen_kept)}')
    # No call site picks between English and Hebrew alone: an EN/HE-only helper, a Hebrew/English literal ternary, or `if he { return
    # "<Hebrew>" }` before English returns (MPResultWords' language switch and the name lists are outside these patterns).
    for path in sorted((ROOT / 'MultiPong').glob('*.swift')):
        if path.name in TEXT_FILES_SKIPPED:
            continue
        text = path.read_text(encoding='utf-8')
        check(not re.search(r'\{\s*(hebrew|he)\s*\?\s*he\s*:\s*en\s*\}', text), f'{path.name}: an English/Hebrew-only tr helper')
        for m in re.finditer(r'\?\s*"([^"\n]*)"\s*:\s*"([^"\n]*)"', text):
            a, b = m.group(1), m.group(2)
            hebrew = [bool(re.search('[֐-׿]', s)) for s in (a, b)]
            latin = [bool(re.search('[A-Za-z]{2}', s)) and not h for s, h in zip((a, b), hebrew)]
            check(not ((hebrew[0] and latin[1]) or (hebrew[1] and latin[0])),
                  f'{path.name}:{text.count(chr(10), 0, m.start()) + 1}: an English/Hebrew-only choice {a[:30]!r} / {b[:30]!r}')
        for m in re.finditer(r'if (he|hebrew) \{ return "[^"\n]*[֐-׿]', text):
            # Allowed when the other languages still go through MPText right after it (CrossText's missed-shot line).
            check('MPText.t(' in text[m.end():m.end() + 400],
                  f'{path.name}:{text.count(chr(10), 0, m.start()) + 1}: an English/Hebrew-only branch')
    compared += 1
    # Fix 1: only 3/4-seat tables save or restore a lineup; a stale `friendlyRoster2` is cleared; the review belongs to its room.
    controller = read('MultiPong/MPController.swift')
    for rule in ['s.participants.values.filter({ $0.bot == nil }).count == 1, s.tableSize >= 3 else { return }',
                 'if s.tableSize < 3 {\n            if !preferences.friendlyRoster(s.tableSize).isEmpty { preferences.setFriendlyRoster(s.tableSize, "") }',
                 'var reviewRestoredRoster: Bool { reviewRestoredRoom != nil && reviewRestoredRoom == session?.id }',
                 'reviewRestoredRoom = ready.id',
                 # Fix 2: no Loading page while this player's own Ready is still needed, before and after the transaction.
                 '!((try? change(s)).map { awaitsOwnReady($0) } ?? false) { loadingMatch = true }',
                 'if updated != nil, self.loadingMatch, self.session?.code == code, let room = latest ?? updated, self.awaitsOwnReady(room) {',
                 'guard s.kind == .friendly, s.state == "ACTIVE", MPRules.friendlyHouseReady(s, actor: uid) == s else { return false }',
                 # Fix 3 call sites: the team room through MPText, the knockout's place number.
                 ]:
        check(rule.replace('\n', '\r\n') in controller or rule in controller, f'MPController lacks the 2026-11-10 fix: {rule[:70]}')
        compared += 1
    check('s.tableSize > 1 else { return }' not in controller, 'MPController still saves 2-seat lineups')
    check('func tr(_ en: String, _ he: String) -> String { MPText.t(en, he, hebrew) }' in read('MultiPong/MPXTeams.swift'),
          'the online team room does not translate through MPText')
    check('let place = !he && MPText.columns.contains(MPText.language) ? String(rank) : ordinal(rank)' in read('MultiPong/MPKnockout.swift'),
          'the tournament place keeps an English ordinal in translations')
    return compared + 3


def main():
    # Non-ASCII failure texts must not crash a Windows console (cp1252).
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(errors='backslashreplace')
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--android', help='path to the MinikCrossPong checkout (read-only)')
    parser.add_argument('--write-catalog', action='store_true', help='regenerate MultiPong/MPTextCatalog.swift from --android')
    args = parser.parse_args()

    if args.write_catalog:
        if not args.android:
            print('--write-catalog needs --android')
            return 2
        source = android_file(pathlib.Path(args.android), APP_TEXT)
        rows = android_rows(source.decode('utf-8'))
        write_catalog(rows, hashlib.sha256(source).hexdigest())
        print(f'Wrote {CATALOG.relative_to(ROOT)}: {len(rows)} rows')
        return 0

    view = read('MultiPong/ModernPongView.swift')
    models = read('MultiPong/MPMultiplayerModels.swift')
    controller = read('MultiPong/MPController.swift')
    check(re.search(r'struct ModernPongView: View', view), 'ModernPongView is missing')
    check('init(experience: ModernPongExperience = .full, commerce: MinikCommerceController? = nil, onClose: @escaping (ModernPongResult?) -> Void' in view,
          'ModernPongView(experience:commerce:onClose:) changed')
    check(re.search(r'enum ModernPongExperience: String, Codable \{\s*case full, simple', models), 'ModernPongExperience changed')
    check('struct ModernPongResult: Codable, Equatable { var playerPoints: Int; var opponentPoints: Int; var won: Bool }' in controller,
          'ModernPongResult changed')

    repository = read('MultiPong/MPRepository.swift')
    check('database.reference().child("minikCrossPong")' in repository, 'Firebase root is not minikCrossPong')
    check('static let appName = "minik-cross-pong"' in repository, 'Firebase app name is not minik-cross-pong')
    check('static let bundleIdentifier = "com.appsbybros.minik.crosspong"' in repository, 'bundle id check changed')
    for other in ('child("minikPingPong")', 'child("tripleShot")', '"minik-ping-pong"'):
        check(other not in repository, f'MPRepository.swift references {other}')

    ads = read('MultiPong/MPAds.swift')
    check(re.search(r'func interstitialUnit\(experience: ModernPongExperience\) -> String\? \{ nil \}', ads), 'an ad unit is configured')
    for path in sorted((ROOT / 'MultiPong').glob('*.swift')):
        check('ca-app-pub-' not in path.read_text(encoding='utf-8'), f'{path.name} contains an AdMob ID')

    rules_path = ROOT / 'Tests' / 'MultiPongFirebase' / 'rules' / 'merged.json'
    rules = json.loads(rules_path.read_text(encoding='utf-8'))['rules']
    check(rules.get('.read') is False and rules.get('.write') is False, 'merged rules open the root')
    check('minikCrossPong' in rules and 'minikPingPong' in rules and 'tripleShot' in rules, 'merged rules lack a subtree')
    check('minikCrossTeams' in rules, 'merged rules lack the team-room root minikCrossTeams (5c1aa4d)')
    # 5c1aa4d: the fragment adds minikCrossPong/receptionPreferences (in the merged candidate since Android cae4ee6).
    fragment = json.loads((ROOT / 'Tests' / 'MultiPongFirebase' / 'rules' / 'crosspong.fragment.json').read_text(encoding='utf-8'))['rules']
    check('receptionPreferences' in fragment.get('minikCrossPong', {}), 'the minikCrossPong fragment lacks receptionPreferences (5c1aa4d)')
    for name in ('minikPingPong', 'minikCrossPong', 'minikPongTeams', 'minikCrossTeams'):
        check('slow' in rules.get(name, {}).get('receptionPreferences', {}).get('$uid', {}), f'merged rules lack {name}/receptionPreferences (cae4ee6)')
    check('leaderboard' not in rules.get('minikCrossPong', {}), 'minikCrossPong has a leaderboard rule')
    committed, worktree = documented_hashes()
    # Stage 4 (2026-11-09): the rules mirror follows Android STAGE1_COMMIT (dd94c09), byte for byte (check_stage4), not the
    # ANDROID_COMMIT hash recorded in the document.

    team_room = read('MultiPong/CrossTeamRoom.swift')
    check('static let protocolName = "cross-teams-v1"' in team_room, 'the team protocol name changed')
    check(team_room.count('"minikCrossTeams/') >= 3, 'the team rooms left the minikCrossTeams root')
    assets = ROOT / 'Resources' / 'MultiPongAssets.xcassets'
    for name in ['mpx_pose_atlas.dataset', 'mpx_menu_music.dataset', 'mpx_sunset_portrait.imageset', 'mpx_sunset_landscape.imageset',
                 'mpx_menu_portrait.imageset', 'mpx_menu_landscape.imageset', 'mpx_tournament_remove.imageset']:
        check((assets / name / 'Contents.json').is_file(), f'MultiPongAssets lacks {name}')
    for character in ['minik', 'miniko', 'coach67', 'kyra', 'flare', 'gaya', 'mia', 'amber', 'comet', 'june', 'moshiko']:
        for name in [f'mpx_pose_{character}', f'mpx_pose_{character}_walk', f'mpx_team_{character}']:
            check((assets / (name + '.imageset') / 'Contents.json').is_file(), f'MultiPongAssets lacks {name}')

    for path in sorted((ROOT / 'Tests' / 'MultiPongTests').glob('*.swift')):
        check('@testable import MinikMultiPingPong' in path.read_text(encoding='utf-8'), f'{path.name} lacks @testable import')
    for folder in ('MultiPong', 'Tests/MultiPongTests'):
        for path in sorted((ROOT / folder).glob('*.swift')):
            check(balanced(path.read_text(encoding='utf-8')), f'{folder}/{path.name}: unbalanced brackets')

    # Languages: MPText, the target's CFBundleLocalizations and the catalog columns agree.
    text_source = read('MultiPong/MPText.swift')
    declared = re.search(r'static let languages: Set<String> = \[([^\]]*)\]', text_source)
    check(declared and sorted(re.findall(r'"([a-z]+)"', declared.group(1))) == sorted(LANGUAGES), 'MPText.languages changed')
    columns = re.search(r'static let columns = \[([^\]]*)\]', text_source)
    check(columns and re.findall(r'"([a-z]+)"', columns.group(1)) == COLUMNS, 'MPText.columns changed')
    project = read('project.yml')
    target = re.search(r'\n  MinikMultiPingPong:\n(.*?)\n  [A-Za-z]\w*:\n', project, re.S)
    localizations = target and re.search(r'CFBundleLocalizations: \[([^\]]*)\]', target.group(1))
    check(localizations and sorted(v.strip() for v in localizations.group(1).split(',')) == sorted(LANGUAGES),
          'CFBundleLocalizations of MinikMultiPingPong differs from the six app languages')
    try:
        catalog = swift_rows(CATALOG.read_text(encoding='utf-8'))
        check_catalog(catalog)
    except (OSError, ValueError, IndexError) as error:
        catalog = []
        failures.append(f'MPTextCatalog.swift could not be read: {error}')
    table = {key: values for _, key, values in catalog}
    sources = ''.join(path.read_text(encoding='utf-8') for path in sorted((ROOT / 'MultiPong').glob('*.swift')) if path != CATALOG)
    try:
        overrides = resource_overrides(text_source)
        check_overrides(overrides, table, sources)
    except (ValueError, IndexError) as error:
        overrides = {}
        failures.append(f'MPText.resourceTexts could not be read: {error}')

    # Stage 1 (2026-11-09): read from --android, or from the MinikCrossPong checkout next to this repository.
    stage1_android = pathlib.Path(args.android) if args.android else ROOT.parent.parent / 'MinikCrossPong'
    try:
        print(f'Stage-1 values compared with Android {STAGE1_COMMIT[:7]}: {check_stage1(stage1_android, sources)}')
    except (OSError, ValueError, IndexError, AttributeError) as error:
        failures.append(f'stage-1 Android comparison failed ({stage1_android}): {error}')
    try:
        print(f'Stage-2 values compared with Android {STAGE1_COMMIT[:7]}: {check_stage2(stage1_android, sources)}')
    except (OSError, ValueError, IndexError, AttributeError) as error:
        failures.append(f'stage-2 Android comparison failed ({stage1_android}): {error}')
    try:
        print(f'Stage-3 values compared with Android {STAGE1_COMMIT[:7]}: {check_stage3(stage1_android, sources)}')
    except (OSError, ValueError, IndexError, AttributeError) as error:
        failures.append(f'stage-3 Android comparison failed ({stage1_android}): {error}')
    try:
        print(f'Stage-4 values compared with Android {STAGE1_COMMIT[:7]}: {check_stage4(stage1_android, sources)}')
    except (OSError, ValueError, IndexError, AttributeError) as error:
        failures.append(f'stage-4 Android comparison failed ({stage1_android}): {error}')
    try:
        print(f'Stage-5 values compared with Android {STAGE1_COMMIT[:7]}: {check_stage5(stage1_android, sources)}')
    except (OSError, ValueError, IndexError, AttributeError) as error:
        failures.append(f'stage-5 Android comparison failed ({stage1_android}): {error}')
    try:
        print(f'iOS-only fixes (2026-11-10) checked: {check_ios_fixes(stage1_android, sources)}')
    except (OSError, ValueError, IndexError, AttributeError) as error:
        failures.append(f'iOS-only fix check failed ({stage1_android}): {error}')

    if args.android:
        android = pathlib.Path(args.android)
        for rel, expected in sorted(committed.items()):
            blob = subprocess.run(['git', '-C', str(android), 'show', f'{ANDROID_COMMIT}:{rel}'], capture_output=True)
            if blob.returncode != 0:
                failures.append(f'Android file missing at {ANDROID_COMMIT[:7]}: {rel}')
                continue
            check(hashlib.sha256(blob.stdout).hexdigest() == expected, f'Android file changed: {rel}')
        # Stage 5: the files the audit compares (the "working-tree" list) are read as committed at ANDROID_COMMIT.
        for rel, expected in sorted(worktree.items()):
            try:
                content = android_file(android, rel)
            except OSError:
                failures.append(f'Android file missing at {ANDROID_COMMIT[:7]}: {rel}')
                continue
            check(hashlib.sha256(content).hexdigest() == expected, f'Android file changed at {ANDROID_COMMIT[:7]}: {rel}')
        check(APP_TEXT in worktree, f'{APP_TEXT} is not listed in the working-tree hashes')
        try:
            source = android_file(android, APP_TEXT)
            expected_rows = android_rows(source.decode('utf-8'))
            check([(c, k, v) for c, k, v in catalog] == [(c, k, v) for c, k, v in expected_rows],
                  'MPTextCatalog.swift differs from the Android AppText.kt (run with --write-catalog)')
            check(hashlib.sha256(source).hexdigest() in CATALOG.read_text(encoding='utf-8'), 'MPTextCatalog.swift names another AppText.kt')
            print(f'Catalog rows compared with Android: {len(expected_rows)}')
        except (OSError, ValueError, IndexError) as error:
            failures.append(f'Android AppText.kt could not be read: {error}')
        for suffix in [''] + ['-' + lang for lang in COLUMNS]:
            check(STRINGS.format(suffix) in worktree, f'{STRINGS.format(suffix)} is not listed in the working-tree hashes')
        try:
            compared = check_resources(android, table, overrides)
            print(f'Android strings.xml texts compared with MPText: {compared}')
        except (OSError, ValueError, IndexError) as error:
            failures.append(f'Android strings.xml could not be compared: {error}')
        for suffix in [''] + list(FOLDERS.values()):
            check(JOURNEY.format(suffix) in worktree, f'{JOURNEY.format(suffix)} is not listed in the working-tree hashes')
        try:
            compared = check_journey(android, journey_texts(text_source))
            print(f'Android journey.xml texts compared with MPText: {compared}')
        except (OSError, ValueError, IndexError) as error:
            failures.append(f'Android journey.xml could not be compared: {error}')
        for suffix in [''] + list(FOLDERS.values()):
            check(ISSUE.format(suffix) in worktree, f'{ISSUE.format(suffix)} is not listed in the working-tree hashes')
        try:
            compared = check_journey(android, journey_texts(text_source, 'issueTexts'), ISSUE, 'issueTexts')
            print(f'Android issue_review.xml texts compared with MPText: {compared}')
        except (OSError, ValueError, IndexError) as error:
            failures.append(f'Android issue_review.xml could not be compared: {error}')
        print(f'Android hashes checked: {len(committed)} at {ANDROID_COMMIT[:7]}, {len(worktree)} compared files at {ANDROID_COMMIT[:7]}')

    if failures:
        print('FAILED')
        for message in failures:
            print(' -', message)
        return 1
    print('OK: Multi Ping Pong static audit passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
