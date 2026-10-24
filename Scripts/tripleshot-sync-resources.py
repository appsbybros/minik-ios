#!/usr/bin/env python3
r"""Copies the Android TripleShot (Minik Swish) resources into TripleShot/Res for the iOS port.

The iOS TripleShot app is a faithful port of the Android app com.appsbybros.minik.swish. Its resources are
the Android ones, used as they are: this script reads the Android project's app/src/main/res and
app/src/main/assets (read only) and writes TripleShot/Res:

  drawable-nodpi/*, drawable/*   every bitmap drawable, byte for byte (XML drawables are ported in Swift;
                                 their names are listed in R.drawable)
  raw/*                          audio, byte for byte, except Ogg Vorbis (*.ogg), which iOS cannot decode:
                                 each is decoded and written as raw/<name>.caf (16-bit ALAC, same rate and
                                 channels, lossless from the decoded samples). A conversion is reused while
                                 the .ogg is unchanged, so only a changed .ogg needs numpy and soundfile.
  assets/question_banks/**       the XML question banks (incl. en/), byte for byte
  strings/he.json                every <string>, <plurals> and <string-array> of values/ (the default,
                                 Hebrew), resolved exactly like aapt2 does it: whitespace collapsing, the
                                 leading/trailing whitespace trim, "quoted" spans, \n \t \' \" \@ \? \#
                                 \\ \uXXXX escapes, CDATA, entities, comments, xliff:g, @string
                                 references. Format strings stay in Java syntax (AFormat).
  strings/en.json                the same for an English device: values-en/, each resource missing there
                                 falling back to values/ like Android ("untranslated" lists them).
  strings/android.json           the android.R.string texts the code uses (android.R.string.cancel), in every
                                 language the Android framework translates them to (resolved for the device
                                 language at runtime, like Android).
  drawable-sizes.json            file and pixel width/height of every image (PNG, WebP VP8/VP8L/VP8X, JPEG,
                                 GIF headers): Android's size for drawable-nodpi and for BitmapFactory with
                                 inScaled=false.
  R.swift                        enum R (string, plurals, array, drawable, mipmap, raw, color, dimen, layout,
                                 id, style) with the Android names, the android.R entries the code uses,
                                 and AResourceIndex (names per type, for AResources.getIdentifier).
  android-source.json            the Android commit, sha256 of every copied file, the generated files and
                                 the source XML files they come from.

Anything the script cannot reproduce exactly (another locale or density folder, 9-patch images, an
unknown resource type, @null strings, theme attributes in strings, ...) stops the run instead of being
copied wrongly. Files copied by an earlier run that no longer exist on Android are removed. Run from
anywhere:

    python Scripts/tripleshot-sync-resources.py [--android <Android project root>] [--family <MinikFamilyServices root>] [--check]

--android defaults to the Android project C:/Projects/TripleShotGame (only read; git runs with
--no-optional-locks); pass a read-only snapshot folder to sync a fixed commit instead. The commit comes
from SNAPSHOT_COMMIT, or from git for a repository (which must then have no local changes under
app/src/main); a repository's app/src/main is read as committed (git archive, no CRLF conversion of a
Windows checkout), so it gives the same bytes as a snapshot of that commit. --family is only read for the android.R.* names its Java code uses (compiled into the app).
--check writes nothing and exits 1 when TripleShot/Res is not up to date.
"""
import argparse
import hashlib
import json
import re
import shutil
import io
import struct
import subprocess
import sys
import tarfile
import tempfile
import xml.parsers.expat
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'TripleShot' / 'Res'
MANIFEST = 'android-source.json'
DEFAULT_ANDROID = Path(r'C:\Projects\TripleShotGame')
RES = 'app/src/main/res'
ASSETS = 'app/src/main/assets'
CODE = 'app/src/main/java'
FAMILY_CODE = 'android/src/main/java'
GIT = shutil.which('git') or r'C:\Program Files\Git\cmd\git.exe'

# Ogg Vorbis raw files: AVAudioFile cannot read them, so they become CAF/ALAC (see the docstring).
CONVERTED_RAW = {'.ogg': '.caf'}
CONVERSION = 'Ogg Vorbis decoded with libsndfile (soundfile), 16-bit, written as CAF ALAC_16'
# Conversions of the previous run (from its android-source.json): target -> sha256 of the source file.
PREVIOUS_CONVERSIONS = {}

# values/ is the default and Hebrew; values-en is English. No other locale exists (DESIGN 2.7).
LOCALES = {'': 'he', 'en': 'en'}
COPIED_DRAWABLE_FOLDERS = ('drawable-nodpi', 'drawable')
IMAGE_EXTENSIONS = ('.png', '.webp', '.jpg', '.jpeg', '.gif')
COPIED_ASSET_FOLDERS = ('question_banks/',)
XLIFF = 'urn:oasis:names:tc:xliff:document:1.2'
NS_SEP = '\x01'
# C isspace() in the "C" locale: what aapt2 collapses and trims.
WS = ' \t\n\v\f\r'
# aapt2 ResourceUtils ParseResourceType.
RESOURCE_TYPES = {'anim', 'animator', 'array', 'attr', '^attr-private', 'bool', 'color', 'configVarying', 'dimen',
                  'drawable', 'font', 'fraction', 'id', 'integer', 'interpolator', 'layout', 'macro', 'menu',
                  'mipmap', 'navigation', 'plurals', 'raw', 'string', 'style', 'styleable', 'transition', 'xml'}
PLURAL_QUANTITIES = ('zero', 'one', 'two', 'few', 'many', 'other')
# Styled strings (<b>, <i>, ... inside a string) would lose their spans: stop unless a test harness allows it.
ALLOW_STYLED_STRINGS = False
# An app string whose value is @android:string/x shows the framework text of the DEVICE language on Android; the
# per-table JSON can only hold one text per table (values/ also serves third-language devices): stop unless a
# test harness allows the he/en resolution.
ALLOW_FRAMEWORK_REFERENCES = False

# android.R entries used by the app (and the family code compiled into it). Ids and values checked against
# platforms/android-36 (android.jar, data/res/values*/strings.xml and data/res/values/colors.xml).
# color -> ARGB; attr -> framework attr id; layout/style -> names.
# string -> {language: text}: the framework's own translations, resolved at runtime for the DEVICE locale like
# Android does (a French device shows "Annuler" in the app's Hebrew dialogs); '' is the default (values/).
# Taken from every data/res/values-*/strings.xml of android-36 with this script's aapt2 rules (quotes removed,
# \u escapes resolved); regional folders that repeat their language's text are folded into the language
# (values-iw -> he, values-in -> id, values-b+sr+Latn -> sr-Latn; the en-rXC pseudo-locale is left out).
FRAMEWORK_CANCEL = {
    '': 'Cancel', 'af': 'Kanselleer', 'am': 'ይቅር', 'ar': 'إلغاء', 'as': 'বাতিল কৰক', 'az': 'Ləğv edin',
    'be': 'Скасаваць', 'bg': 'Отказ', 'bn': 'বাতিল করুন', 'bs': 'Otkaži', 'ca': 'Cancel·la', 'cs': 'Zrušit',
    'da': 'Annuller', 'de': 'Abbrechen', 'el': 'Ακύρωση', 'es': 'Cancelar', 'et': 'Tühista', 'eu': 'Utzi',
    'fa': 'لغو', 'fi': 'Peru', 'fr': 'Annuler', 'gl': 'Cancelar', 'gu': 'રદ કરો', 'he': 'ביטול',
    'hi': 'रद्द करें', 'hr': 'Odustani', 'hu': 'Mégse', 'hy': 'Չեղարկել', 'id': 'Batal', 'is': 'Hætta við',
    'it': 'Annulla', 'ja': 'キャンセル', 'ka': 'გაუქმება', 'kk': 'Бас тарту', 'km': 'បោះ​បង់​',
    'kn': 'ರದ್ದುಮಾಡಿ', 'ko': '취소', 'ky': 'Жокко чыгаруу', 'lo': 'ຍົກເລີກ', 'lt': 'Atšaukti', 'lv': 'Atcelt',
    'mk': 'Откажи', 'ml': 'റദ്ദാക്കുക', 'mn': 'Цуцлах', 'mr': 'रद्द करा', 'ms': 'Batal', 'my': 'မလုပ်တော့',
    'nb': 'Avbryt', 'ne': 'रद्द गर्नुहोस्', 'nl': 'Annuleren', 'or': 'ବାତିଲ କରନ୍ତୁ', 'pa': 'ਰੱਦ ਕਰੋ',
    'pl': 'Anuluj', 'pt': 'Cancelar', 'ro': 'Anulează', 'ru': 'Отмена', 'si': 'අවලංගු කරන්න', 'sk': 'Zrušiť',
    'sl': 'Prekliči', 'sq': 'Anulo', 'sr': 'Откажи', 'sr-Latn': 'Otkaži', 'sv': 'Avbryt', 'sw': 'Ghairi',
    'ta': 'ரத்துசெய்', 'te': 'రద్దు చేయండి', 'th': 'ยกเลิก', 'tl': 'Kanselahin', 'tr': 'İptal',
    'uk': 'Скасувати', 'ur': 'منسوخ کریں', 'uz': 'Bekor qilish', 'vi': 'Hủy', 'zh': '取消', 'zu': 'Khansela',
}
FRAMEWORK = {
    'string': {'cancel': FRAMEWORK_CANCEL},
    'color': {'transparent': 0x00000000},
    'attr': {'progressBarStyleHorizontal': 16842872, 'textViewStyle': 16842884, 'state_enabled': 16842910,
             'state_focused': 16842908, 'state_pressed': 16842919},
    'layout': {'simple_spinner_item': 'simple_spinner_item',
               'simple_spinner_dropdown_item': 'simple_spinner_dropdown_item'},
    'style': {'Theme_Material_Light_Dialog_Alert': 'Theme.Material.Light.Dialog.Alert'},
}

SWIFT_KEYWORDS = {
    'associatedtype', 'class', 'deinit', 'enum', 'extension', 'fileprivate', 'func', 'import', 'init', 'inout',
    'internal', 'let', 'open', 'operator', 'private', 'precedencegroup', 'protocol', 'public', 'rethrows',
    'static', 'struct', 'subscript', 'typealias', 'var', 'break', 'case', 'catch', 'continue', 'default',
    'defer', 'do', 'else', 'fallthrough', 'for', 'guard', 'if', 'in', 'repeat', 'return', 'throw', 'switch',
    'where', 'while', 'Any', 'as', 'await', 'false', 'is', 'nil', 'self', 'Self', 'super', 'throws', 'true',
    'try', 'Type', 'Protocol',
}


def stop(message):
    print('STOPPED: ' + message)
    sys.exit(1)


# ------------------------------------------------------------------------------------------------------------
# XML (expat, like aapt2's XmlPullParser: namespaces resolved, entities and CDATA as text, comments dropped
# without splitting the text around them)
# ------------------------------------------------------------------------------------------------------------

class Element:
    __slots__ = ('ns', 'name', 'attrs', 'children', 'line')

    def __init__(self, ns, name, attrs, line):
        self.ns, self.name, self.attrs, self.children, self.line = ns, name, attrs, [], line

    def get(self, name, ns=''):
        for (attr_ns, attr_name), value in self.attrs:
            if attr_ns == ns and attr_name == name:
                return value
        return None


def split_name(name):
    ns, sep, local = name.rpartition(NS_SEP)
    return (ns, local) if sep else ('', name)


def parse_xml(data, where):
    parser = xml.parsers.expat.ParserCreate(namespace_separator=NS_SEP)
    parser.ordered_attributes = True
    document = Element('', '#document', [], 0)
    stack = [document]

    def start(name, attrs):
        ns, local = split_name(name)
        pairs = [(split_name(attrs[i]), attrs[i + 1]) for i in range(0, len(attrs), 2)]
        element = Element(ns, local, pairs, parser.CurrentLineNumber)
        stack[-1].children.append(element)
        stack.append(element)

    def end(_name):
        stack.pop()

    def characters(text):
        children = stack[-1].children
        if children and isinstance(children[-1], str):
            children[-1] += text
        else:
            children.append(text)

    parser.StartElementHandler = start
    parser.EndElementHandler = end
    parser.CharacterDataHandler = characters
    try:
        parser.Parse(data, True)
    except xml.parsers.expat.ExpatError as error:
        stop(f'{where}: {error}')
    roots = [child for child in document.children if isinstance(child, Element)]
    if len(roots) != 1:
        stop(f'{where}: no single root element')
    return roots[0]


def walk(element):
    yield element
    for child in element.children:
        if isinstance(child, Element):
            yield from walk(child)


# ------------------------------------------------------------------------------------------------------------
# aapt2 string processing (ResourceParser::FlattenXmlSubtree + ResourceUtils::StringBuilder + ParseXml)
# ------------------------------------------------------------------------------------------------------------

class StringBuilder:
    """aapt2 StringBuilder(preserve_spaces=false)."""

    def __init__(self, where):
        self.where = where
        self.parts = []
        self.utf16 = 0
        self.quote = False
        self.last_was_space = False
        self.spans = []
        self.open_spans = []

    def append_text(self, text):
        out = []
        i, n = 0, len(text)
        while i < n:
            c = text[i]
            i += 1
            if not self.quote and c in WS:
                if not self.last_was_space:
                    out.append(' ')
                    self.last_was_space = True
                continue
            self.last_was_space = False
            if c == '\\':
                if i < n:
                    c = text[i]
                    i += 1
                    if c == 't':
                        out.append('\t')
                    elif c == 'n':
                        out.append('\n')
                    elif c in '#@?"\'\\':
                        out.append(c)
                    elif c == 'u':
                        digits = text[i:i + 4]
                        if len(digits) != 4 or any(d not in '0123456789abcdefABCDEF' for d in digits):
                            stop(f'{self.where}: invalid unicode escape sequence in {text!r}')
                        i += 4
                        code = int(digits, 16)
                        if 0xD800 <= code <= 0xDFFF:
                            stop(f'{self.where}: surrogate \\u escape in {text!r} (check aapt2 before supporting it)')
                        out.append(chr(code))
                    else:
                        # aapt2: ignore the escape character and keep the character.
                        out.append(c)
                # A backslash at the very end of a text segment is dropped.
            elif c == '"':
                self.quote = not self.quote
            elif not self.quote and c == "'":
                stop(f'{self.where}: unescaped apostrophe in string {text!r} (aapt2 rejects it)')
            else:
                out.append(c)
        chunk = ''.join(out)
        self.parts.append(chunk)
        self.utf16 += len(chunk.encode('utf-16-le')) // 2

    def reset_text_state(self):
        # aapt2: "When we start/end a span, all state associated with whitespace truncation and quotation
        # is ended."
        self.quote = False
        self.last_was_space = False

    def start_span(self, name):
        self.reset_text_state()
        self.open_spans.append((name, self.utf16))

    def end_span(self):
        self.reset_text_state()
        name, first = self.open_spans.pop()
        self.spans.append({'name': name, 'start': first, 'end': self.utf16 - 1})

    def text(self):
        return ''.join(self.parts)


def flatten(element, where):
    """FlattenXmlSubtree of the children of a resource element: (raw text, processed text, spans)."""
    raw = []
    segments = []
    saw_span = False

    def build_tree(children):
        nonlocal saw_span
        nodes = []
        current = []
        for child in children:
            if isinstance(child, str):
                current.append(child)
                raw.append(child)
                continue
            if current:
                segment = ['segment', ''.join(current)]
                nodes.append(segment)
                segments.append(segment)
                current = []
            if child.ns == '':
                saw_span = True
                name = child.name + ''.join(f';{attr_name}={value}' for (_ns, attr_name), value in child.attrs)
                nodes.append(['span', name, build_tree(child.children)])
            elif child.ns == XLIFF and child.name == 'g':
                nodes.append(['untranslatable', build_tree(child.children)])
            else:
                nodes.append(['node', build_tree(child.children)])
        if current:
            segment = ['segment', ''.join(current)]
            nodes.append(segment)
            segments.append(segment)
        return nodes

    tree = build_tree(element.children)
    if not saw_span and segments:
        # Without spans aapt2 trims the leading whitespace of the first segment and the trailing whitespace
        # of the last one (before escapes are processed).
        segments[0][1] = segments[0][1].lstrip(WS)
        segments[-1][1] = segments[-1][1].rstrip(WS)

    builder = StringBuilder(where)

    def build(nodes):
        for node in nodes:
            if node[0] == 'segment':
                builder.append_text(node[1])
            elif node[0] == 'span':
                builder.start_span(node[1])
                build(node[2])
                builder.end_span()
            else:
                build(node[1])

    build(tree)
    return ''.join(raw), builder.text(), builder.spans


def extract_resource_name(text):
    """androidfw ExtractResourceName: (package, type, entry), or None when malformed. Like androidfw it skips
    one leading '@' (so "@@string/x" is a reference too)."""
    package = kind = ''
    has_package = has_type = False
    start = 1 if text.startswith('@') else 0
    for i, c in enumerate(text):
        if i < start:
            continue
        if kind == '' and c == '/':
            has_type = True
            kind = text[start:i]
            start = i + 1
        elif package == '' and c == ':':
            has_package = True
            package = text[start:i]
            start = i + 1
    entry = text[start:]
    if (has_package and package == '') or (has_type and kind == ''):
        return None
    return package, kind, entry


def parse_reference(raw):
    """aapt2 ResourceUtils::ParseReference: (package, type, name, create) of an @reference, or None."""
    text = raw.strip(WS)
    if not text.startswith('@'):
        return None
    body = text[1:]
    create = body.startswith('+')
    if create:
        body = body[1:]
    if body.startswith('*'):
        if create:
            return None
        body = body[1:]
    if not body:
        return None
    name = extract_resource_name(body)
    if name is None or name[1] not in RESOURCE_TYPES or not name[2]:
        return None
    if create and name[1] != 'id':
        return None
    return name + (create,)


def is_attribute_reference(raw):
    """aapt2 ResourceUtils::ParseAttributeReference: ?[package:][attr/]entry."""
    text = raw.strip(WS)
    if not text.startswith('?'):
        return False
    name = extract_resource_name(text[1:])
    return name is not None and name[1] in ('', 'attr') and bool(name[2])


def parse_text_item(element, where):
    """ParseXml(TYPE_STRING): ('text', value, spans) or ('ref', type, name)."""
    raw, text, spans = flatten(element, where)
    if spans:
        if not ALLOW_STYLED_STRINGS:
            stop(f'{where}: styled text (<{spans[0]["name"].split(";")[0]}>) is not supported: getString would be '
                 f'exact, but the spans of getText are not carried to iOS yet')
        return ('text', text, spans)
    stripped = raw.strip(WS)
    if stripped in ('@null', '@empty'):
        stop(f'{where}: {stripped} as a string value is not supported')
    if is_attribute_reference(raw):
        stop(f'{where}: theme attribute {stripped} as a string value is not supported')
    reference = parse_reference(raw)
    if reference and reference[3]:
        stop(f'{where}: {stripped} as a string value is not supported')
    if reference:
        package, kind, name, _create = reference
        if package not in ('', 'android') or kind != 'string':
            stop(f'{where}: reference {stripped} is not supported (only @string)')
        if package == 'android':
            if name not in FRAMEWORK['string']:
                stop(f'{where}: framework string {name} unknown to the script')
            return ('ref', 'android:string', name)
        return ('ref', 'string', name)
    return ('text', text, [])


def parse_color(element, where):
    raw, _text, _spans = flatten(element, where)
    reference = parse_reference(raw)
    if reference:
        package, kind, name, _create = reference
        if package == 'android' and kind == 'color' and name in FRAMEWORK['color']:
            return ('value', FRAMEWORK['color'][name])
        if package or kind != 'color':
            stop(f'{where}: color reference {raw.strip(WS)} is not supported')
        return ('ref', name)
    text = raw.strip(WS)
    digits = text[1:]
    if not text.startswith('#') or len(digits) not in (3, 4, 6, 8) or \
            any(d not in '0123456789abcdefABCDEF' for d in digits):
        stop(f'{where}: invalid color {text!r}')
    if len(digits) in (3, 4):
        digits = ''.join(d * 2 for d in digits)
    value = int(digits, 16)
    if len(digits) == 6:
        value |= 0xFF000000
    return ('value', value)


DIMEN_RE = re.compile(r'^([+-]?\d+(?:\.\d+)?|[+-]?\.\d+)(dp|dip|sp|px)$')


def parse_dimen(element, where):
    raw, _text, _spans = flatten(element, where)
    match = DIMEN_RE.match(raw.strip(WS))
    if not match:
        stop(f'{where}: dimension {raw.strip(WS)!r} is not supported (dp, sp, px)')
    unit = 'dp' if match.group(2) == 'dip' else match.group(2)
    # A Swift float literal (".5" is not one).
    return (repr(float(match.group(1))), unit)


# ------------------------------------------------------------------------------------------------------------
# values/ folders
# ------------------------------------------------------------------------------------------------------------

def parse_values_file(path, rel, config, table, sources):
    data = path.read_bytes()
    sources[rel] = data
    resources = parse_xml(data, rel)
    if resources.ns or resources.name != 'resources':
        stop(f'{rel}: root element is not <resources>')
    for child in resources.children:
        if isinstance(child, str):
            if child.strip(WS):
                stop(f'{rel}: plain text {child.strip(WS)!r} inside <resources>')
            continue
        if child.ns:
            continue  # aapt2 skips elements of unknown namespaces
        tag = child.name
        if tag in ('skip', 'eat-comment'):
            continue
        name = child.get('name')
        where = f'{rel}:{child.line} <{tag} name="{name}">'
        if not name:
            stop(f'{rel}:{child.line}: <{tag}> without a name')
        if child.get('product') is not None:
            stop(f'{where}: the product attribute is not supported')
        if tag == 'string':
            kind, value = 'string', parse_text_item(child, where)
        elif tag == 'plurals':
            kind, value = 'plurals', {}
            for item in child.children:
                if isinstance(item, str):
                    continue
                if item.ns == '' and item.name in ('skip', 'eat-comment'):
                    continue
                if item.ns or item.name != 'item':
                    stop(f'{where}: unknown tag <{item.name}> in <plurals>')
                quantity = (item.get('quantity') or '').strip(WS)
                if quantity not in PLURAL_QUANTITIES:
                    stop(f'{where}: invalid quantity {quantity!r}')
                if quantity in value:
                    stop(f'{where}: duplicate quantity {quantity!r}')
                value[quantity] = parse_text_item(item, f'{where} quantity={quantity}')
        elif tag == 'string-array':
            kind, value = 'array', []
            for item in child.children:
                if isinstance(item, str):
                    continue
                if item.ns == '' and item.name in ('skip', 'eat-comment'):
                    continue
                if item.ns or item.name != 'item':
                    stop(f'{where}: unknown tag <{item.name}> in <string-array>')
                value.append(parse_text_item(item, f'{where} item {len(value)}'))
        elif tag == 'color':
            kind, value = 'color', parse_color(child, where)
        elif tag == 'dimen':
            kind, value = 'dimen', parse_dimen(child, where)
        elif tag == 'style':
            kind, value = 'style', name
        else:
            stop(f'{where}: resource type <{tag}> is not supported by the script yet')
        if kind in ('color', 'dimen', 'style') and config != '':
            stop(f'{where}: a {kind} in values-{config} is not supported')
        entries = table.setdefault(config, {}).setdefault(kind, {})
        if name in entries:
            stop(f'{where}: duplicate {kind} {name} in values{"-" + config if config else ""}')
        entries[name] = value


def resolve_text(item, kind, chains, table, language, seen=()):
    """The text of a parsed item for a device whose configurations are `chains` (best first)."""
    if item[0] == 'text':
        return item[1]
    _ref, ref_kind, name = item
    if ref_kind == 'android:string':
        if not ALLOW_FRAMEWORK_REFERENCES:
            stop(f'an app string refers to @android:string/{name}: Android shows the framework text of the device '
                 f'language there, which the string tables cannot express yet')
        texts = FRAMEWORK['string'][name]
        return texts.get(language, texts[''])
    if (ref_kind, name) in seen:
        stop(f'reference cycle through @string/{name}')
    for config in chains:
        target = table.get(config, {}).get('string', {}).get(name)
        if target is not None:
            return resolve_text(target, 'string', chains, table, language, seen + ((ref_kind, name),))
    stop(f'@string/{name} does not exist')


def string_table(table, chains, language):
    out = {'strings': {}, 'plurals': {}, 'arrays': {}}
    origin = {}
    names = {kind: sorted({n for c in chains for n in table.get(c, {}).get(kind, {})})
             for kind in ('string', 'plurals', 'array')}
    for kind, key in (('string', 'strings'), ('plurals', 'plurals'), ('array', 'arrays')):
        for name in names[kind]:
            config = next(c for c in chains if name in table.get(c, {}).get(kind, {}))
            value = table[config][kind][name]
            origin[(kind, name)] = config
            if kind == 'string':
                out[key][name] = resolve_text(value, kind, chains, table, language)
            elif kind == 'plurals':
                out[key][name] = {q: resolve_text(value[q], kind, chains, table, language)
                                  for q in PLURAL_QUANTITIES if q in value}
            else:
                out[key][name] = [resolve_text(v, kind, chains, table, language) for v in value]
    return out, origin


def framework_strings(used):
    """strings/android.json: the android.R.string texts the code uses, per language ('' = the default)."""
    return {name: dict(sorted(FRAMEWORK['string'][name].items())) for name in sorted(used.get('string', ()))}


# ------------------------------------------------------------------------------------------------------------
# Images
# ------------------------------------------------------------------------------------------------------------

def image_size(data, where):
    """Pixel width and height from the file header (what Android decodes; no density scaling)."""
    if data[:8] == b'\x89PNG\r\n\x1a\n':
        if data[12:16] != b'IHDR':
            stop(f'{where}: PNG without IHDR')
        return struct.unpack('>II', data[16:24])
    if data[:4] == b'RIFF' and data[8:12] == b'WEBP':
        chunk = data[12:16]
        if chunk == b'VP8 ':
            if data[20] & 1:
                stop(f'{where}: WebP VP8 data is not a key frame')
            if data[23:26] != b'\x9d\x01\x2a':
                stop(f'{where}: bad WebP VP8 start code')
            width, height = struct.unpack('<HH', data[26:30])
            return width & 0x3FFF, height & 0x3FFF
        if chunk == b'VP8L':
            if data[20] != 0x2F:
                stop(f'{where}: bad WebP VP8L signature')
            bits = struct.unpack('<I', data[21:25])[0]
            return (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
        if chunk == b'VP8X':
            if data[20] & 0x02:
                stop(f'{where}: animated WebP is not supported')
            return int.from_bytes(data[24:27], 'little') + 1, int.from_bytes(data[27:30], 'little') + 1
        stop(f'{where}: unknown WebP chunk {chunk!r}')
    if data[:6] in (b'GIF87a', b'GIF89a'):
        return struct.unpack('<HH', data[6:10])
    if data[:2] == b'\xff\xd8':
        i = 2
        while i + 9 < len(data):
            if data[i] != 0xFF:
                i += 1
                continue
            marker = data[i + 1]
            if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7 or marker == 0xFF:
                i += 1 if marker == 0xFF else 2
                continue
            length = struct.unpack('>H', data[i + 2:i + 4])[0]
            if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                height, width = struct.unpack('>HH', data[i + 5:i + 9])
                return width, height
            i += 2 + length
        stop(f'{where}: JPEG without a frame header')
    stop(f'{where}: unknown image format')


# ------------------------------------------------------------------------------------------------------------
# Source collection
# ------------------------------------------------------------------------------------------------------------

def resource_name(file_name):
    # Android: the resource name is the file name up to the first dot.
    return file_name.split('.', 1)[0]


def android_commit(android):
    # Recorded as the 7-digit abbreviation, so a snapshot (SNAPSHOT_COMMIT may be abbreviated) and the
    # repository at the same commit give the same output.
    snapshot = android / 'SNAPSHOT_COMMIT'
    if snapshot.exists():
        return snapshot.read_text(encoding='utf-8').strip()[:7]
    result = subprocess.run([GIT, '--no-optional-locks', 'rev-parse', 'HEAD'], cwd=android,
                            capture_output=True, text=True)
    if result.returncode:
        stop(f'{android} has neither SNAPSHOT_COMMIT nor a git HEAD')
    changes = subprocess.run([GIT, '--no-optional-locks', 'status', '--porcelain', '--', 'app/src/main'], cwd=android,
                             capture_output=True, text=True)
    if changes.returncode or changes.stdout.strip():
        stop(f'{android} has local changes under app/src/main; commit them first')
    return result.stdout.strip()[:7]


def committed_tree(android, folder):
    """A repository's committed app/src/main extracted into folder (git archive; core.autocrlf off, so the bytes
    are the committed ones, like a snapshot). Only reads the repository."""
    archive = subprocess.run([GIT, '--no-optional-locks', '-c', 'core.autocrlf=false', 'archive', '--format=tar',
                              'HEAD', '--', 'app/src/main'], cwd=android, capture_output=True)
    if archive.returncode:
        stop(f'{android}: git archive failed: {archive.stderr.decode(errors="replace").strip()}')
    with tarfile.open(fileobj=io.BytesIO(archive.stdout)) as tar:
        tar.extractall(folder, filter='data')
    return Path(folder)


def convert_ogg(data, target, where):
    """An Ogg Vorbis file as CAF ALAC 16-bit. The earlier conversion is kept while the source is unchanged."""
    source_sha = hashlib.sha256(data).hexdigest()
    existing = OUT / target
    if PREVIOUS_CONVERSIONS.get(target) == source_sha and existing.exists():
        return existing.read_bytes()
    try:
        import numpy
        import soundfile
    except ImportError:
        stop(f'{where} changed: converting Ogg Vorbis needs numpy and soundfile (pip install soundfile)')
    samples, rate = soundfile.read(io.BytesIO(data), dtype='float64', always_2d=True)
    # Clipped like the 16-bit output of Android's Vorbis decoder (libsndfile itself would wrap).
    pcm = numpy.clip(numpy.rint(samples * 32768.0), -32768, 32767).astype(numpy.int16)
    out = io.BytesIO()
    soundfile.write(out, pcm, rate, format='CAF', subtype='ALAC_16')
    result = out.getvalue()
    check, check_rate = soundfile.read(io.BytesIO(result), dtype='int16', always_2d=True)
    if check_rate != rate or check.shape != pcm.shape or not (check == pcm).all():
        stop(f'{where}: the ALAC conversion does not read back sample for sample')
    return result


def collect(android, family):
    res = android / RES
    assets = android / ASSETS
    code = android / CODE
    if not res.is_dir() or not code.is_dir():
        stop(f'{android} is not the TripleShot Android project (no {RES} or {CODE})')

    copied = {}        # Res-relative path -> bytes
    sizes = {}         # drawable name -> (file, width, height)
    xml_drawables = set()
    names = {kind: set() for kind in ('drawable', 'mipmap', 'raw', 'layout', 'id', 'style')}
    raw_files = {}
    converted = {}     # converted raw file -> its source path
    table = {}
    colors = {}
    dimens = {}
    sources = {}       # source path (relative to the project) -> bytes, for the manifest
    defined_ids, referenced_ids = set(), set()

    for folder in sorted(p for p in res.iterdir() if p.is_dir()):
        kind, _, qualifiers = folder.name.partition('-')
        files = sorted(p for p in folder.iterdir() if p.is_file())
        rel_folder = f'{RES}/{folder.name}'
        if not any(folder.iterdir()):
            # An empty folder (git keeps none; one can linger in a working tree) holds no resources for aapt2.
            continue
        if kind == 'values':
            if qualifiers not in LOCALES:
                stop(f'{rel_folder}: only values/ and values-en/ are supported (DESIGN 2.7)')
            for path in files:
                if path.suffix != '.xml':
                    stop(f'{rel_folder}/{path.name}: not an XML file')
                parse_values_file(path, f'{rel_folder}/{path.name}', qualifiers, table, sources)
        elif kind == 'drawable':
            if folder.name not in COPIED_DRAWABLE_FOLDERS:
                stop(f'{rel_folder}: density/qualified drawable folders are not supported')
            for path in files:
                name = resource_name(path.name)
                where = f'{rel_folder}/{path.name}'
                if name in names['drawable']:
                    stop(f'{where}: drawable {name} exists twice (Android would pick one by density)')
                names['drawable'].add(name)
                lower = path.name.lower()
                if lower.endswith('.9.png'):
                    stop(f'{where}: 9-patch images are not supported')
                if lower.endswith('.xml'):
                    xml_drawables.add(name)
                    data = path.read_bytes()
                    sources[where] = data
                    scan_ids(parse_xml(data, where), defined_ids, referenced_ids)
                    continue
                if not lower.endswith(IMAGE_EXTENSIONS) or path.name.count('.') != 1:
                    stop(f'{where}: unexpected drawable file')
                data = path.read_bytes()
                target = f'{folder.name}/{path.name}'
                width, height = image_size(data, where)
                copied[target] = data
                sizes[name] = (target, width, height)
        elif kind == 'mipmap':
            # Launcher icons: not needed at runtime (the iOS app icon is separate); names only.
            for path in files:
                names['mipmap'].add(resource_name(path.name))
                if path.suffix == '.xml':
                    data = path.read_bytes()
                    sources[f'{rel_folder}/{path.name}'] = data
                    scan_ids(parse_xml(data, f'{rel_folder}/{path.name}'), defined_ids, referenced_ids)
        elif kind == 'raw':
            if qualifiers:
                stop(f'{rel_folder}: qualified raw folders are not supported')
            for path in files:
                name = resource_name(path.name)
                if name in names['raw']:
                    stop(f'{rel_folder}/{path.name}: raw {name} exists twice')
                names['raw'].add(name)
                data = path.read_bytes()
                if path.suffix in CONVERTED_RAW:
                    target = f'raw/{name}{CONVERTED_RAW[path.suffix]}'
                    sources[f'{rel_folder}/{path.name}'] = data
                    converted[target] = f'{rel_folder}/{path.name}'
                    data = convert_ogg(data, target, f'{rel_folder}/{path.name}')
                else:
                    target = f'raw/{path.name}'
                raw_files[name] = target
                copied[target] = data
        elif kind == 'layout':
            if qualifiers not in ('', 'land'):
                stop(f'{rel_folder}: only layout/ and layout-land/ are supported')
            for path in files:
                where = f'{rel_folder}/{path.name}'
                names['layout'].add(resource_name(path.name))
                data = path.read_bytes()
                sources[where] = data
                scan_ids(parse_xml(data, where), defined_ids, referenced_ids)
        else:
            stop(f'{rel_folder}: resource folder type {kind!r} is not supported by the script yet')

    # aapt2 link: "removing resource ... without required default value" (a string only in values-en).
    for config in [c for c in table if c != '']:
        for kind in ('string', 'plurals', 'array'):
            for name in sorted(table[config].get(kind, {})):
                if name not in table.get('', {}).get(kind, {}):
                    print(f'warn: removing {kind}/{name} of values-{config} without a default value (as aapt2)')
                    del table[config][kind][name]
    for config in table:
        for name, value in table[config].get('color', {}).items():
            colors[name] = value
        for name, value in table[config].get('dimen', {}).items():
            dimens[name] = value
        for name in table[config].get('style', {}):
            names['style'].add(name)
    for path in sorted(res.glob('values*/*.xml')):
        scan_ids(parse_xml(path.read_bytes(), str(path)), defined_ids, referenced_ids)

    resolved_colors = {}

    def color_value(name, seen=()):
        if name in seen:
            stop(f'color reference cycle through {name}')
        if name not in colors:
            stop(f'@color/{name} does not exist')
        value = colors[name]
        if value[0] == 'ref':
            return color_value(value[1], seen + (name,))
        return value[1]

    for name in colors:
        resolved_colors[name] = color_value(name)

    if assets.is_dir():
        skipped = sorted({p.relative_to(assets).as_posix().split('/')[0] for p in assets.rglob('*') if p.is_file()}
                         - {f.rstrip('/') for f in COPIED_ASSET_FOLDERS})
        for path in sorted(p for p in assets.rglob('*') if p.is_file()):
            rel = path.relative_to(assets).as_posix()
            if rel.startswith(COPIED_ASSET_FOLDERS):
                copied['assets/' + rel] = path.read_bytes()
        if skipped:
            print(f'Not copied (not used by the port): assets/{", assets/".join(skipped)}')

    # The R and android.R names the code uses (the family code is compiled into the app but has no R).
    def read_code(root):
        return '\n'.join(path.read_text(encoding='utf-8') for path in sorted(root.rglob('*'))
                         if path.suffix in ('.kt', '.java') and path.is_file())

    app_code = read_code(code)
    family_code = read_code(family / FAMILY_CODE) if family and (family / FAMILY_CODE).is_dir() else ''
    used_framework = {}
    for kind, name in sorted(set(re.findall(r'\bandroid\.R\.([a-z]+)\.([A-Za-z_][A-Za-z0-9_]*)',
                                            app_code + '\n' + family_code))):
        if name not in FRAMEWORK.get(kind, {}):
            stop(f'the code uses android.R.{kind}.{name}, unknown to the script: add it to FRAMEWORK')
        used_framework.setdefault(kind, set()).add(name)
    code_refs = set(re.findall(r'(?<![\w.])R\.([a-z]+)\.([A-Za-z_][A-Za-z0-9_]*)', app_code))
    referenced_ids |= {name for kind, name in code_refs if kind == 'id'}
    missing = sorted(referenced_ids - defined_ids)
    if missing:
        stop(f'ids used but never defined with @+id: {", ".join(missing)}')
    names['id'] = defined_ids
    # Every other R.<type>.<name> of the code must exist too (the Android build guarantees it).
    known = {
        'string': set(table.get('', {}).get('string', {})), 'plurals': set(table.get('', {}).get('plurals', {})),
        'array': set(table.get('', {}).get('array', {})), 'color': set(colors), 'dimen': set(dimens),
        'style': names['style'], 'id': defined_ids,
        **{kind: names[kind] for kind in ('drawable', 'mipmap', 'raw', 'layout')},
    }
    # The code names R fields, where '.' is '_' (aapt2 JavaClassGenerator).
    known = {kind: {n.replace('.', '_') for n in values} for kind, values in known.items()}
    unknown = sorted(f'R.{kind}.{name}' for kind, name in code_refs if name not in known.get(kind, set()))
    if unknown:
        stop(f'the code uses resources the snapshot does not define: {", ".join(unknown[:20])}')

    return {
        'copied': copied, 'sizes': sizes, 'xml_drawables': xml_drawables, 'names': names,
        'raw_files': raw_files, 'converted': converted, 'table': table, 'colors': resolved_colors, 'dimens': dimens,
        'sources': sources, 'framework': used_framework,
    }


def scan_ids(root, defined, referenced):
    for element in walk(root):
        for (_ns, _name), value in element.attrs:
            text = value.strip(WS)
            if text.startswith('@+id/'):
                defined.add(text[5:])
            elif text.startswith('@id/'):
                referenced.add(text[4:])
            elif text.startswith(('@+android:id/', '@android:id/')):
                stop(f'framework id {text} is not supported')


# ------------------------------------------------------------------------------------------------------------
# Output
# ------------------------------------------------------------------------------------------------------------

def swift_name(name):
    # aapt2 JavaClassGenerator: '.' in a resource name becomes '_' in the R field (Theme.TripleShot ->
    # R.style.Theme_TripleShot).
    field = name.replace('.', '_')
    return f'`{field}`' if field in SWIFT_KEYWORDS else field


def swift_string(text):
    return '"' + text.replace('\\', '\\\\').replace('"', '\\"') + '"'


def signed32(value):
    return value - (1 << 32) if value & 0x80000000 else value


def r_swift(found, commit):
    names, table = found['names'], found['table']
    string_names = sorted({n for c in table for n in table[c].get('string', {})})
    plural_names = sorted({n for c in table for n in table[c].get('plurals', {})})
    array_names = sorted({n for c in table for n in table[c].get('array', {})})
    lines = [
        '// Generated by Scripts/tripleshot-sync-resources.py from the Android TripleShot resources',
        f'// (com.appsbybros.minik.swish, commit {commit}). Do not edit: run the script again.',
        '//',
        '// The Android R class with the same names. A resource id is the resource NAME here (AStringRes,',
        '// ADrawableRes and ARawRes are String), so resId-keyed maps and lists keep working, and an id that',
        "// Android's getIdentifier would return 0 for is nil (AResources.getIdentifier). R.color holds the",
        '// ARGB colour itself (a sign-extended 32-bit Int, as @ColorInt). R.dimen is in px (getDimension).',
        '',
        'enum R {',
    ]

    def section(kind, entries):
        fields = [entry.split(':')[0].split()[-1] for entry in entries]
        clashes = sorted({f for f in fields if fields.count(f) > 1})
        if clashes:
            stop(f'R.{kind}: two resources map to the same field name: {", ".join(clashes)}')
        lines.append(f'    enum {kind} {{')
        lines.extend(entries)
        lines.append('    }')

    section('string', [f'        static let {swift_name(n)}: AStringRes = {swift_string(n)}' for n in string_names])
    section('plurals', [f'        static let {swift_name(n)}: AStringRes = {swift_string(n)}' for n in plural_names])
    section('array', [f'        static let {swift_name(n)}: AStringRes = {swift_string(n)}' for n in array_names])
    section('drawable', [f'        static let {swift_name(n)}: ADrawableRes = {swift_string(n)}'
                         for n in sorted(names['drawable'])])
    section('mipmap', [f'        static let {swift_name(n)}: ADrawableRes = {swift_string(n)}'
                       for n in sorted(names['mipmap'])])
    section('raw', [f'        static let {swift_name(n)}: ARawRes = {swift_string(n)}' for n in sorted(names['raw'])])
    section('color', [f'        static let {swift_name(n)}: Int = {signed32(v)}  // #{v:08X}'
                      for n, v in sorted(found['colors'].items())])
    dimen_lines = []
    for name, (number, unit) in sorted(found['dimens'].items()):
        factor = {'dp': ' * AResources.displayMetrics.density', 'sp': ' * AResources.displayMetrics.scaledDensity',
                  'px': ''}[unit]
        dimen_lines.append(f'        static var {swift_name(name)}: Float {{ Float({number}){factor} }}  // {number}{unit}')
    section('dimen', dimen_lines)
    section('layout', [f'        static let {swift_name(n)}: String = {swift_string(n)}' for n in sorted(names['layout'])])
    section('id', [f'        static let {swift_name(n)}: String = {swift_string(n)}' for n in sorted(names['id'])])
    section('style', [f'        static let {swift_name(n)}: String = {swift_string(n)}' for n in sorted(names['style'])])
    lines.append('}')
    lines.append('')

    framework = found['framework']
    lines += [
        '/// android.R: the framework resources the Android code uses (the values of android-36). Strings are',
        '/// "android:<name>": AResources resolves them in the device language (Res/strings/android.json), like the',
        '/// framework; colours are ARGB like R.color; attrs keep the framework attribute ids; layouts and styles are',
        '/// names.',
        'enum android {',
        '    enum R {',
    ]
    for kind in ('string', 'color', 'attr', 'layout', 'style'):
        entries = sorted(framework.get(kind, ()))
        if not entries:
            continue
        lines.append(f'        enum {kind} {{')
        for name in entries:
            value = FRAMEWORK[kind][name]
            if kind == 'string':
                lines.append(f'            static let {swift_name(name)}: AStringRes = {swift_string("android:" + name)}')
            elif kind == 'color':
                lines.append(f'            static let {swift_name(name)}: Int = {signed32(value)}  // #{value:08X}')
            elif kind == 'attr':
                lines.append(f'            static let {swift_name(name)}: Int = {value}')
            else:
                lines.append(f'            static let {swift_name(name)}: String = {swift_string("android:" + value)}')
        lines.append('        }')
    lines += ['    }', '}', '']

    def name_list(values):
        out, line = [], ''
        for value in values:
            item = swift_string(value) + ','
            if line and len(line) + 1 + len(item) > 112:
                out.append('        ' + line)
                line = ''
            line = f'{line} {item}' if line else item
        if line:
            out.append('        ' + line)
        return out

    lines += [
        '/// The resource table behind AResources.getIdentifier and drawableExists: every name per type.',
        '/// Bitmap drawables, their files and pixel sizes are in Res/drawable-sizes.json; strings, plurals and',
        '/// arrays in Res/strings/*.json.',
        'enum AResourceIndex {',
        '    /// Drawables defined in XML (ported in Swift, no bitmap file).',
        '    static let xmlDrawables: Set<String> = [',
        *name_list(sorted(found['xml_drawables'])),
        '    ]',
        '    /// Raw resource name -> file below Res/.',
        '    static let rawFiles: [String: String] = [',
        *[f'        {swift_string(n)}: {swift_string(f)},' for n, f in sorted(found['raw_files'].items())],
        '    ]',
        '    static let mipmap: Set<String> = [',
        *name_list(sorted(names['mipmap'])),
        '    ]',
        '    static let color: Set<String> = [',
        *name_list(sorted(found['colors'])),
        '    ]',
        '    static let dimen: Set<String> = [' if found['dimens'] else '    static let dimen: Set<String> = []',
    ]
    if found['dimens']:
        lines += [*name_list(sorted(found['dimens'])), '    ]']
    lines += [
        '    static let layout: Set<String> = [',
        *name_list(sorted(names['layout'])),
        '    ]',
        '    static let id: Set<String> = [',
        *name_list(sorted(names['id'])),
        '    ]',
        '    static let style: Set<String> = [',
        *name_list(sorted(names['style'])),
        '    ]',
        '}',
        '',
    ]
    return '\n'.join(lines).encode('utf-8')


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=1) + '\n').encode('utf-8')


def generate(found, commit):
    table = found['table']
    generated = {}
    he, he_origin = string_table(table, [''], 'he')
    en, en_origin = string_table(table, ['en', ''], 'en')
    untranslated = sorted({f'{kind}/{name}' if kind != 'string' else name
                           for (kind, name), config in en_origin.items() if config != 'en'})
    generated['strings/he.json'] = json_bytes({
        'language': 'he', 'source': 'values', 'commit': commit, **he})
    generated['strings/en.json'] = json_bytes({
        'language': 'en', 'source': 'values-en, then values', 'commit': commit, **en,
        'untranslated': untranslated})
    generated['strings/android.json'] = json_bytes({
        'language': 'android', 'source': 'Android SDK platforms/android-36 data/res/values*/strings.xml (framework)',
        'strings': framework_strings(found['framework'])})
    lines = ['{']
    entries = sorted(found['sizes'].items())
    for i, (name, (file, width, height)) in enumerate(entries):
        comma = ',' if i + 1 < len(entries) else ''
        lines.append(f' {json.dumps(name)}: {{"file": {json.dumps(file)}, "width": {width}, "height": {height}}}{comma}')
    lines.append('}')
    generated['drawable-sizes.json'] = ('\n'.join(lines) + '\n').encode('utf-8')
    generated['R.swift'] = r_swift(found, commit)
    return generated, len(he['strings']), len(en['strings']), len(untranslated)


def main():
    # Messages may quote Hebrew text; never fail on a console that cannot print it.
    sys.stdout.reconfigure(errors='backslashreplace')
    arguments = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    arguments.add_argument('--android', type=Path, default=DEFAULT_ANDROID)
    arguments.add_argument('--family', type=Path, default=None)
    arguments.add_argument('--check', action='store_true')
    options = arguments.parse_args()
    android = options.android.resolve()
    family = options.family
    if family is None:
        for candidate in (android.parent / 'family', android.parent / 'MinikFamilyServices'):
            if candidate.is_dir():
                family = candidate
                break
    commit = android_commit(android)
    manifest_path = OUT / MANIFEST
    old = json.loads(manifest_path.read_text(encoding='utf-8')) if manifest_path.exists() else {}
    for target, record in old.get('converted', {}).items():
        # Trusted only while the converted file is the one that run wrote.
        written = old.get('files', {}).get(target)
        if written and (OUT / target).exists() and hashlib.sha256((OUT / target).read_bytes()).hexdigest() == written:
            PREVIOUS_CONVERSIONS[target] = record['sha256']
    if (android / 'SNAPSHOT_COMMIT').exists():
        found = collect(android, family)
    else:
        with tempfile.TemporaryDirectory(prefix='tripleshot-res-') as folder:
            found = collect(committed_tree(android, folder), family)
    generated, he_count, en_count, untranslated = generate(found, commit)

    files = dict(found['copied'])
    manifest = json_bytes({
        'android': {'repository': 'TripleShotGame', 'commit': commit, 'res': RES, 'assets': ASSETS},
        'framework': 'android.R values of the Android SDK platforms/android-36 (data/res, android.jar), '
                     'kept in this script (FRAMEWORK)',
        'generated': {path: hashlib.sha256(data).hexdigest() for path, data in sorted(generated.items())},
        'sources': {path: hashlib.sha256(data).hexdigest() for path, data in sorted(found['sources'].items())},
        'files': {path: hashlib.sha256(data).hexdigest() for path, data in sorted(files.items())},
        'converted': {target: {'source': source, 'sha256': hashlib.sha256(found['sources'][source]).hexdigest(),
                               'conversion': CONVERSION}
                      for target, source in sorted(found['converted'].items())},
    })
    outputs = {**files, **generated, MANIFEST: manifest}

    previous = set(old.get('files', {})) | set(old.get('generated', {}))
    stale = sorted(p for p in previous - set(outputs) if (OUT / p).exists())
    changed = sorted(p for p, data in outputs.items()
                     if not (OUT / p).exists() or (OUT / p).read_bytes() != data)
    if options.check:
        for path in stale:
            print(f'stale: {path}')
        for path in changed:
            print(f'out of date: {path}')
        sys.exit(1 if stale or changed else 0)
    for path in stale:
        (OUT / path).unlink()
        print(f'removed {path}')
    for path in changed:
        target = OUT / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(outputs[path])
    images = len(found['sizes'])
    image_bytes = sum(len(found['copied'][f]) for f, _w, _h in found['sizes'].values())
    raw_bytes = sum(len(d) for p, d in files.items() if p.startswith('raw/'))
    asset_files = [p for p in files if p.startswith('assets/')]
    asset_bytes = sum(len(files[p]) for p in asset_files)
    print(f'TripleShot Android {commit[:7]}: {he_count} he strings, {en_count} en strings ({untranslated} from values/), '
          f'{images} images ({image_bytes} bytes), {len(found["raw_files"])} raw ({raw_bytes} bytes), '
          f'{len(asset_files)} assets ({asset_bytes} bytes), {len(found["xml_drawables"])} XML drawables, '
          f'{len(found["names"]["id"])} ids; {len(outputs)} files, {len(changed)} written, {len(stale)} removed.')


if __name__ == '__main__':
    main()
