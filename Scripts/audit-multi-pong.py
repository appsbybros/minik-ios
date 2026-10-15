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

With --android <path to the MinikCrossPong checkout>, it also
  * re-hashes every Android file listed in the handoff document: the committed blobs of ANDROID_COMMIT, and the
    working-tree files listed in its "working-tree files" section;
  * compares MultiPong/MPTextCatalog.swift row by row with the Android AppText.kt of that working tree;
  * compares every string of the working tree's values-es, -ar, -hi and -nl strings.xml (Android getString) with the text
    MPText shows for its English text: the catalog row, or MPText.resourceTexts where Android's resource text differs;
  * compares every string of the working tree's values*/journey.xml (5c1aa4d) with MPText.journeyTexts.

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
ANDROID_COMMIT = '1dbfe336d39da5cf8a6e396541ff60378303d210'
APP_TEXT = 'app/src/main/java/com/appsbybros/minik/localization/AppText.kt'
STRINGS = 'app/src/main/res/values{}/strings.xml'
JOURNEY = 'app/src/main/res/values{}/journey.xml'
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
    receptionAssistance2026 first and journey2026 last; a later group's value wins for a repeated key, as in Kotlin)."""
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
    return rows


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
    english = android_strings((android / STRINGS.format('')).read_text(encoding='utf-8'))
    used, compared = set(), 0
    for column, lang in enumerate(COLUMNS):
        local = android_strings((android / STRINGS.format('-' + lang)).read_text(encoding='utf-8'))
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


def journey_texts(text):
    """MPText.journeyTexts of MPText.swift: {(English text, language): text}."""
    block = re.search(r'static let journeyTexts: \[String: \[String: String\]\] = \[\n(.*?)\n    \]\n', text, re.S)
    if not block:
        raise ValueError('MPText.journeyTexts is missing')
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


def check_journey(android, texts):
    """Android values*/journey.xml (getString) against MPText.journeyTexts. Returns the number of strings compared."""
    english = android_strings((android / JOURNEY.format('')).read_text(encoding='utf-8'))
    compared = 0
    for name, key in sorted(english.items()):
        for lang, folder in FOLDERS.items():
            local = android_strings((android / JOURNEY.format(folder)).read_text(encoding='utf-8'))
            check(texts.get((key, lang)) == local.get(name), f'journey.xml {name} ({lang}): Android shows {local.get(name)!r}, MPText {texts.get((key, lang))!r}')
            compared += 1
    check(len(texts) == compared, 'MPText.journeyTexts has a text that no Android journey.xml has')
    return compared


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--android', help='path to the MinikCrossPong checkout (read-only)')
    parser.add_argument('--write-catalog', action='store_true', help='regenerate MultiPong/MPTextCatalog.swift from --android')
    args = parser.parse_args()

    if args.write_catalog:
        if not args.android:
            print('--write-catalog needs --android')
            return 2
        source = (pathlib.Path(args.android) / APP_TEXT).read_bytes()
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
    # Hashed with LF line endings: a Windows checkout (core.autocrlf) writes CRLF into the working file.
    merged_hash = hashlib.sha256(rules_path.read_bytes().replace(b'\r\n', b'\n')).hexdigest()
    check(committed.get('firebase-setup/merged-database-rules.json') == merged_hash, 'rules/merged.json differs from the documented Android candidate')

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

    if args.android:
        android = pathlib.Path(args.android)
        for rel, expected in sorted(committed.items()):
            blob = subprocess.run(['git', '-C', str(android), 'show', f'{ANDROID_COMMIT}:{rel}'], capture_output=True)
            if blob.returncode != 0:
                failures.append(f'Android file missing at {ANDROID_COMMIT[:7]}: {rel}')
                continue
            check(hashlib.sha256(blob.stdout).hexdigest() == expected, f'Android file changed: {rel}')
        for rel, expected in sorted(worktree.items()):
            path = android / rel
            if not path.is_file():
                failures.append(f'Android working-tree file missing: {rel}')
                continue
            check(hashlib.sha256(path.read_bytes()).hexdigest() == expected, f'Android working-tree file changed: {rel}')
        check(APP_TEXT in worktree, f'{APP_TEXT} is not listed in the working-tree hashes')
        try:
            source = (android / APP_TEXT).read_bytes()
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
        print(f'Android hashes checked: {len(committed)} at {ANDROID_COMMIT[:7]}, {len(worktree)} in the working tree')

    if failures:
        print('FAILED')
        for message in failures:
            print(' -', message)
        return 1
    print('OK: Multi Ping Pong static audit passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
