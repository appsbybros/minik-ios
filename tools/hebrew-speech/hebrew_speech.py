"""Recorded Hebrew speech for Minik Plus (HebrewRecordedSpeech.swift).

    python tools/hebrew-speech/hebrew_speech.py [--app mathplus] texts
        Lists every Hebrew text the app says (texts.tsv) and checks the phrase keys.
        --app picks the app: plus (Minik Plus, the default) or mathplus (Minik Math Plus,
        Resources/HebrewSpeechMath/HebrewSpeech, texts-mathplus.tsv, recorded-mathplus.json).
        Every command takes it.
    python tools/hebrew-speech/hebrew_speech.py record --voice he-IL-HilaNeural
        Records the texts that have no clip yet, or whose text or voice changed, into
        Resources/HebrewSpeech, and writes its manifest.json. Needs the user environment
        variables AZURE_SPEECH_KEY and AZURE_SPEECH_REGION (an Azure Speech resource).
        Run it with a Python that has miniaudio (pip install miniaudio).
    python tools/hebrew-speech/hebrew_speech.py trim
        Cuts the silent tail off the clips already recorded (record does it for new ones).
    python tools/hebrew-speech/hebrew_speech.py review
        Writes one page to listen to every clip, with the clips inside it, so it can be
        copied anywhere (tools/hebrew-speech/review/index.html; not committed).

A clip is filed under key(text), the rule HebrewRecordedSpeech.key follows in the app. What
is recorded may differ from what the app says: respellings.tsv changes single words
(ת'שובות for תשובות) and overrides.tsv whole texts; the clip stays filed under the app's
text. After changing either, run `record` again: only the changed clips are re-recorded.

Math Plus puts sentences together from its clips (HebrewRecordedSpeech.clipFiles), so its
clips are recorded as PCM and cut close at both ends before they are encoded (needs lameenc).
"""

import argparse
import hashlib
import http.client
import html
import json
import os
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
CLIPS = REPO / 'Resources' / 'HebrewSpeech'
CATALOG = REPO / 'Resources' / 'Localization' / 'All' / 'Localizable.xcstrings'
VOCABULARY = REPO / 'Resources' / 'Vocabulary' / 'words-normalized.xml'
ALPHABET = REPO / 'Sources' / 'LanguageLearnContentProvider.swift'
RECORDED = HERE / 'recorded.json'

SEPARATORS = set('.,!?…:;"״“”„()[]-–—־/')
APOSTROPHES = set('׳‘’`´')


def key(text):
    """HebrewRecordedSpeech.key: no points, punctuation or case; one space between words."""
    out, pending_space = [], False
    chars = unicodedata.normalize('NFC', text.lower())
    for index, ch in enumerate(chars):
        if 0x0591 <= ord(ch) <= 0x05C7 and unicodedata.category(ch) == 'Mn':
            continue
        inside_number = (ch in '.,' and not pending_space and out and '0' <= out[-1] <= '9'
                         and index + 1 < len(chars) and '0' <= chars[index + 1] <= '9')
        if not inside_number and (ch.isspace() or ch in SEPARATORS):
            pending_space = bool(out)
            continue
        if pending_space:
            out.append(' ')
            pending_space = False
        out.append("'" if ch in APOSTROPHES else ch)
    return ''.join(out)


def clip_name(text_key):
    return 'he-' + hashlib.sha1(text_key.encode('utf-8')).hexdigest()[:12] + '.mp3'


# ---- What the app says in Hebrew ----------------------------------------------------------------------------------------

# Interface phrases spoken in Hebrew (catalog keys). Where each is said:
PHRASE_KEYS = {
    # LanguageEncouragementCopy, LanguageWordEncouragement (LanguageFeedbackSoundPlayer.swift)
    'encouragement': [
        'Great game!', 'Success!', 'Great job!', 'Nice!', 'Fun game', 'Awesome!', 'Excellent!', 'Fantastic!',
        'Good!', 'Very nice!', 'Correct', 'Amazing!', 'Keep up the good work!', 'Correct answer!',
        'Brilliant!', 'You are on a streak!', 'You are learning fast!', 'Magnificent!',
    ],
    # LanguageTowerPraise (TowerView.swift)
    'tower': ['Tower complete! A new word is coming next.'],
    # TicTacToeFeedbackCopy (TicTacToeFeedbackPlayer.swift)
    'tic-tac-toe': [
        'Tic Tac Toe — Just for Fun!', 'Pick X or O, or just tap a square to start!', 'You won!',
        'It’s a tie!', 'Tie game!', 'Draw', 'We lost this time. Hope it was fun!', 'A new round begins',
    ],
    # LanguageSoccerView.swift: goals and the match result
    'soccer': ['Goal', 'Minik won!'],
    # MemoryView.swift: languageFlipTwoCardsText's fallback
    'memory': ['Turn over two cards to find a match.'],
}

# LanguageSoccerView.soccerIntroductionText: these lines, then the closing line, one per line.
SOCCER_INTRODUCTION = [
    'Drag the letters in the correct order to spell the word shown.',
    'Try to score a goal against Minik with each letter.',
    'Correct letter + goal = 1 point for you!',
    'Wrong letter + no goal = 1 point for Minik!',
    'Tap Start to begin. Good luck!',
]

# Hebrew said as written in the code, with no catalog key.
FIXED_HEBREW = {
    'memory': 'לחצו על משבצת כדי להפוך אותה',            # MemoryView.speakLanguageIntroductionIfNeeded
    'menu': 'בחרו תרגול כדי להתחיל',                     # LanguageMenuAndroidText.selectScreenVoice
}
FIXED_ENGLISH = {'memory': 'Tap a tile to turn it over', 'menu': 'Choose a practice to start'}

# LearningSpeechPlayer.enqueuePracticeEncouragement: "<run> correct answers in a row" from 3 on.
STREAK_RUNS = range(3, 51)

# A lone letter is said by name. Pointed, so the voice cannot guess (אלף is also "thousand");
# בית, גימל, טית, למד and תו as the owner chose them by ear (2026-10-28).
LETTER_NAMES = {
    'א': 'אָלֶף', 'ב': 'בֵּת', 'ג': 'גימל', 'ד': 'דָּלֶת', 'ה': 'הֵא', 'ו': 'וָו', 'ז': 'זַיִן',
    'ח': 'חֵית', 'ט': 'טֵת', 'י': 'יוּד', 'כ': 'כָּף', 'ל': '{ˈlamed|לָמֵד}', 'מ': 'מֵם', 'נ': 'נוּן',
    'ס': 'סָמֶךְ', 'ע': 'עַיִן', 'פ': 'פֵּא', 'צ': 'צָדִי', 'ק': 'קוּף', 'ר': 'רֵישׁ', 'ש': 'שִׁין',
    'ת': '{tav|תָּיו}',
}
FINAL_LETTERS = {'ך': 'כ', 'ם': 'מ', 'ן': 'נ', 'ף': 'פ', 'ץ': 'צ'}

# LanguageVocabularyCatalogLoader.legacyHebrewSpeechText: said instead of the Hebrew word.
LEGACY_SPEECH = {'fruits_kiwi': 'Kiwi'}


def catalog_hebrew():
    strings = json.loads(CATALOG.read_text(encoding='utf-8'))['strings']

    def hebrew(catalog_key):
        unit = strings.get(catalog_key, {}).get('localizations', {}).get('he', {}).get('stringUnit', {})
        value = unit.get('value')
        if not value:
            sys.exit(f'No Hebrew for catalog key {catalog_key!r}')
        return value
    return hebrew


def read_table(name):
    """Two tab-separated columns; # starts a comment; \\n is a line break."""
    rows = {}
    path = HERE / name
    if path.exists():
        for line in path.read_text(encoding='utf-8').splitlines():
            if line.strip() and not line.lstrip().startswith('#'):
                written, spoken = line.replace('\\n', '\n').split('\t')
                rows[written.strip()] = spoken.strip()
    return rows


def respell(text, respellings):
    """Whole-word replacements, longest first; a word already replaced by "{ipa|word}" is left alone.
    Quote marks around a button name (״הוספה״) are dropped: Hila read them as part of the word."""
    text = re.sub(r'״(?=[֐-׿])|(?<=[֐-׿])״(?![֐-׿])', '', text)
    for written in sorted(respellings, key=len, reverse=True):
        pieces = re.split(r'(\{[^{}]*\})', text)
        text = ''.join(piece if piece.startswith('{') else
                       re.sub(r'(?<![\w֐-׿])' + re.escape(written) + r'(?![\w֐-׿])', respellings[written], piece)
                       for piece in pieces)
    return text


def collect():
    """key -> {'text': what the app says, 'record': what is recorded, 'sources': [...],
    'english': [what it means, for the review page]}."""
    hebrew = catalog_hebrew()
    respellings, overrides = read_table('respellings.tsv'), read_table('overrides.tsv')
    texts = {}

    def add(text, source, record=None, english=None):
        k = key(text)
        if not k:
            return
        entry = texts.setdefault(k, {'text': text, 'record': None, 'sources': [], 'english': []})
        if record and not entry['record']:
            entry['record'] = record
        if source not in entry['sources']:
            entry['sources'].append(source)
        if english and english not in entry['english']:
            entry['english'].append(english)

    for element in ET.parse(VOCABULARY).getroot().iter('word'):
        word = element.get('he')
        if word:
            add(word, 'word', english=element.get('en'))
        legacy = LEGACY_SPEECH.get(element.get('key'))
        if legacy:
            add(legacy, 'word', record=word, english=element.get('en'))

    alphabet = ALPHABET.read_text(encoding='utf-8')
    hebrew_alphabet = alphabet[alphabet.index('static let hebrewAlphabet'):]
    hebrew_alphabet = hebrew_alphabet[:hebrew_alphabet.index('\n    ]')]
    for line in re.findall(r'AlphabetItem\(key:[^\n]*', hebrew_alphabet):
        letter, word = re.search(r'letter: "([^"]+)", word: "([^"]+)"', line).groups()
        spoken = re.search(r'spokenLetter: "([^"]+)"', line)
        spoken = spoken and spoken.group(1)
        letter_key = re.search(r'key: "([^"]+)"', line).group(1)
        add(word, 'alphabet word', english=f'the picture word for {letter_key}')
        if letter in FINAL_LETTERS:
            name = LETTER_NAMES[FINAL_LETTERS[letter]] + ' סוֹפִית'
            add(spoken or letter, 'letter', record=name, english=f'the letter {letter_key}')
            add(letter, 'letter', record=name, english=f'the letter {letter_key}')
        else:
            add(letter, 'letter', record=LETTER_NAMES[letter], english=f'the letter {letter_key}')

    for source, keys in PHRASE_KEYS.items():
        for catalog_key in keys:
            add(hebrew(catalog_key), source, english=catalog_key)
    add('\n'.join(hebrew(k) for k in SOCCER_INTRODUCTION), 'soccer introduction',
        english=' '.join(SOCCER_INTRODUCTION))
    for source, text in FIXED_HEBREW.items():
        add(text, source, english=FIXED_ENGLISH[source])
    for run in STREAK_RUNS:
        add(f'{run} {hebrew("correct answers in a row")}', 'streak', english=f'{run} correct answers in a row')

    for entry in texts.values():
        record = entry['record'] or entry['text']
        entry['record'] = overrides.get(entry['text'], respell(record, respellings))
    return texts


def write_texts(texts):
    lines = ['key\trecorded text\tsaid for']
    for k, entry in sorted(texts.items()):
        lines.append('\t'.join([k, entry['record'].replace('\n', ' / '), ', '.join(entry['sources'])]))
    (HERE / APP['texts']).write_text('\n'.join(lines) + '\n', encoding='utf-8')


# Minik Math Plus: every catalog text (instructions, how-to cards, rule cards, praise, the
# words for + − × ÷ < = >), split at its number placeholders, and the numbers its exercises
# are read with. MathReadAloud reads "3 + □ = 7" as "3 ועוד כמה שווה 7"; the app puts that
# together from these clips.
MATH_NUMBERS = range(0, 1001)
PLACEHOLDER = re.compile(r'%(?:\d+\$)?(?:lld|ld|lu|llu|d|i|u|@|(?:\.\d+)?f)')


def collect_mathplus():
    strings = json.loads(CATALOG.read_text(encoding='utf-8'))['strings']
    respellings, overrides = read_table('respellings.tsv'), read_table('overrides.tsv')
    texts = {}

    def add(text, source, english=None):
        k = key(text)
        if any(ch.isalnum() for ch in k):  # not a lone symbol left between placeholders
            entry = texts.setdefault(k, {'text': text.strip(), 'record': None, 'sources': [], 'english': []})
            if source not in entry['sources']:
                entry['sources'].append(source)
            if english and english not in entry['english']:
                entry['english'].append(english)

    def units(localization):
        if 'stringUnit' in localization:
            yield localization['stringUnit'].get('value') or ''
        for variants in localization.get('variations', {}).values():
            for variant in variants.values():
                yield from units(variant)

    for catalog_key, entry in strings.items():
        for value in units(entry.get('localizations', {}).get('he', {})):
            for piece in PLACEHOLDER.split(value):
                add(piece, 'catalog', english=catalog_key if piece.strip() == value.strip() else f'part of: {catalog_key}')
    for number in MATH_NUMBERS:
        add(str(number), 'number', english=str(number))
        add(f'{number:,}', 'number', english=str(number))  # 1,000 as the Hebrew locale writes it
    for entry in texts.values():
        entry['record'] = overrides.get(entry['text'], respell(entry['text'], respellings))
    return texts


# ---- Recording ----------------------------------------------------------------------------------------------------------

# "{kaˈtsav|קצב}" in a recorded text is said exactly as the IPA before the bar (Hila follows
# it, stress included), for words that vowel marks don't fix.
PHONEME = re.compile(r'\{([^{}|]+)\|([^{}]+)\}')


def synthesize(text, voice, region, secret, output_format='audio-24khz-48kbitrate-mono-mp3'):
    lines = [html.escape(line.strip()) for line in text.split('\n') if line.strip()]
    body = PHONEME.sub(r"<phoneme alphabet='ipa' ph='\1'>\2</phoneme>", '<break time="500ms"/>'.join(lines))
    ssml = (f"<speak version='1.0' xml:lang='he-IL'><voice name='{voice}'>{body}</voice></speak>").encode('utf-8')
    request = urllib.request.Request(
        f'https://{region}.tts.speech.microsoft.com/cognitiveservices/v1', data=ssml, method='POST',
        headers={
            'Ocp-Apim-Subscription-Key': secret,
            'Content-Type': 'application/ssml+xml',
            'X-Microsoft-OutputFormat': output_format,
            'User-Agent': 'minik-hebrew-speech',
        })
    for attempt in range(8):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code in (429, 500, 502, 503, 504) and attempt < 7:
                wait = int(error.headers.get('Retry-After') or 0) or 15 * (attempt + 1)
                print(f'  Azure answered {error.code}; waiting {wait} s')
                time.sleep(wait)
                continue
            sys.exit(f'Azure answered {error.code}: {error.read()[:300]!r}')
        except (urllib.error.URLError, TimeoutError, ConnectionError, http.client.HTTPException) as error:
            if attempt < 7:
                print(f'  {error!r}; trying again')
                time.sleep(10)
                continue
            sys.exit(f'Could not reach Azure: {error}')


def user_variable(name):
    """The environment variable, or on Windows the user variable set after this terminal opened."""
    if os.environ.get(name):
        return os.environ[name]
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, 'Environment') as variables:
            return winreg.QueryValueEx(variables, name)[0]
    except (ImportError, OSError):
        return None


# Azure returns at least 1.8 s, so a short word ends in a second of silence, and the app waits
# for a clip to end before it says the next thing. The tail is cut at whole MP3 frames (this
# format's frames are all 144 bytes, 24 ms), so nothing is re-encoded.
FRAME_BYTES, FRAME_SECONDS, TAIL_SECONDS = 144, 0.024, 0.15


def trim(data):
    """The clip without its silent tail (needs miniaudio; see the record command)."""
    import miniaudio
    decoded = miniaudio.decode(data, output_format=miniaudio.SampleFormat.SIGNED16, nchannels=1, sample_rate=24000)
    loud = [i for i, sample in enumerate(decoded.samples) if abs(sample) > 500]
    if not loud or len(data) % FRAME_BYTES:
        return data
    end = loud[-1] / 24000 + TAIL_SECONDS
    frames = int(end / FRAME_SECONDS) + 3
    return data[:min(len(data), frames * FRAME_BYTES)]


# Math Plus: 30 ms before the voice starts and 80 ms after it ends, encoded like Azure's MP3s.
LEAD_SECONDS, CLOSE_TAIL_SECONDS = 0.03, 0.08


def synthesize_close(text, voice, region, secret):
    """An MP3 cut close at both ends: Azure's PCM, trimmed, then encoded (needs lameenc)."""
    import array
    import io
    import wave
    with wave.open(io.BytesIO(synthesize(text, voice, region, secret, 'riff-24khz-16bit-mono-pcm'))) as audio:
        rate = audio.getframerate()
        samples = array.array('h', audio.readframes(audio.getnframes()))
    loud = [i for i, sample in enumerate(samples) if abs(sample) > 500]
    if loud:
        start = max(0, loud[0] - int(LEAD_SECONDS * rate))
        samples = samples[start:loud[-1] + int(CLOSE_TAIL_SECONDS * rate)]
    return encode(samples, rate)


# "✂468-905✂{biχ.ˈʁu|בחרו} משחק …": the text is recorded whole and only 468 ms to 905 ms of it is
# kept, for a word Hila says right only inside a sentence (Azure records a text the same way
# every time, so the times stay right).
CUT = re.compile(r'^✂(\d+)-(\d+)✂')


def synthesize_cut(text, voice, region, secret):
    import array
    import io
    import wave
    cut = CUT.match(text)
    with wave.open(io.BytesIO(synthesize(text[cut.end():], voice, region, secret, 'riff-24khz-16bit-mono-pcm'))) as audio:
        rate = audio.getframerate()
        samples = array.array('h', audio.readframes(audio.getnframes()))
    piece = samples[int(cut.group(1)) * rate // 1000:int(cut.group(2)) * rate // 1000]
    fade = min(int(0.005 * rate), len(piece) // 2)
    for i in range(fade):
        piece[i] = int(piece[i] * i / fade)
        piece[-1 - i] = int(piece[-1 - i] * i / fade)
    quiet = array.array('h', [0])
    return encode(quiet * int(LEAD_SECONDS * rate) + piece + quiet * int(CLOSE_TAIL_SECONDS * rate), rate)


# "…בסוף ‖{ha.ki.ˈʃu|הקישו} על בדיקת התשובה.": the text is recorded whole, and from the mark on it is
# replaced by the rest recorded as a sentence of its own, where Hila stresses a word the way she
# does at the start of a sentence. The two meet at the quietest moment near the mark (best a
# voiceless sound, such as the ף before the ה).
SPLIT = '‖'


def synthesize_split(text, voice, region, secret, pause=0.0):
    import array
    import io
    import wave

    def pcm(said):
        with wave.open(io.BytesIO(synthesize(said, voice, region, secret, 'riff-24khz-16bit-mono-pcm'))) as audio:
            return audio.getframerate(), array.array('h', audio.readframes(audio.getnframes()))

    rate, whole = pcm(text.replace(SPLIT, ''))
    time.sleep(pause)
    _, rest = pcm(text.split(SPLIT, 1)[1])
    loud = [i for i, sample in enumerate(rest) if abs(sample) > 500]
    rest = rest[max(0, loud[0] - int(0.04 * rate)):loud[-1] + int(CLOSE_TAIL_SECONDS * rate)]
    loud_whole = [i for i, sample in enumerate(whole) if abs(sample) > 500]
    # Where the rest starts inside the whole: the place where the loudness (every 10 ms) of the
    # rest's first 0.6 s best matches the whole's.
    step = rate // 100

    def loudness(samples):
        return [sum(abs(sample) for sample in samples[i:i + step]) / step for i in range(0, len(samples) - step, step)]

    whole_env, rest_env = loudness(whole), loudness(rest)[:60]

    def match(at):
        part = whole_env[at:at + len(rest_env)]
        if len(part) < len(rest_env):
            return -1
        mean_a, mean_b = sum(part) / len(part), sum(rest_env) / len(rest_env)
        a, b = [x - mean_a for x in part], [x - mean_b for x in rest_env]
        return sum(x * y for x, y in zip(a, b)) / ((sum(x * x for x in a) * sum(y * y for y in b)) ** 0.5 or 1)

    end = loud_whole[-1] // step
    start = max(range(max(0, end - len(loudness(rest)) - 60), max(1, end - len(loudness(rest)) + 60)), key=match)
    guess, window = (start + 4) * step, int(0.03 * rate)  # the rest has 40 ms before its first loud sound
    quietest = min(range(max(0, guess - int(0.04 * rate)), guess + int(0.01 * rate), int(0.005 * rate)),
                   key=lambda at: sum(abs(sample) for sample in whole[at:at + window]))
    out = whole[max(0, loud_whole[0] - int(LEAD_SECONDS * rate)):quietest + window // 2]
    overlap = int(0.01 * rate)
    for i in range(overlap):  # the end of the whole text fades into the rest
        weight = i / overlap
        out[len(out) - overlap + i] = int(out[len(out) - overlap + i] * (1 - weight) + rest[i] * weight)
    out.extend(rest[overlap:])
    return encode(out, rate)


def encode(samples, rate):
    import lameenc
    encoder = lameenc.Encoder()
    encoder.set_bit_rate(48)
    encoder.set_in_sample_rate(rate)
    encoder.set_channels(1)
    encoder.set_quality(2)
    return bytes(encoder.encode(samples.tobytes()) + encoder.flush())


# "מִיס⁀חַק": the parts recorded apart and put end to end in one clip, for a word Hila
# otherwise says with a vowel between them. "⁀150⁀" cuts 150 ms off the end of the part
# before (Hila draws out a word's last sound), "⁀150,40⁀" also 40 ms off the start of the
# part after (its soft beginning); a part that starts with "70%" is played that loud (so the
# stress falls on the next part).
JOIN = re.compile(r'⁀(?:(\d+)(?:,(\d+))?⁀)?')
GAIN = re.compile(r'^(\d+)%')


def synthesize_joined(text, voice, region, secret, pause=0.0):
    import array
    import io
    import wave
    pieces = JOIN.split(text)
    parts = pieces[0::3]
    cuts, starts = [int(ms or 0) for ms in pieces[1::3]], [int(ms or 0) for ms in pieces[2::3]]
    out, rate = array.array('h'), 24000
    for index, part in enumerate(parts):
        gain = GAIN.match(part)
        part, gain = (part[gain.end():], int(gain.group(1)) / 100) if gain else (part, 1.0)
        with wave.open(io.BytesIO(synthesize(part, voice, region, secret, 'riff-24khz-16bit-mono-pcm'))) as audio:
            rate = audio.getframerate()
            samples = array.array('h', audio.readframes(audio.getnframes()))
        if index < len(parts) - 1:
            time.sleep(pause)
        loud = [i for i, sample in enumerate(samples) if abs(sample) > 500]
        lead = LEAD_SECONDS if index == 0 else 0.005
        tail = (CLOSE_TAIL_SECONDS if APP['close'] else TAIL_SECONDS) if index == len(parts) - 1 else 0.01
        piece = [int(sample * gain) for sample in samples[max(0, loud[0] - int(lead * rate)):loud[-1] + int(tail * rate)]]
        if index:
            del out[max(0, len(out) - int(cuts[index - 1] * rate / 1000)):]
            del piece[:int(starts[index - 1] * rate / 1000)]
        overlap = min(int(0.01 * rate), len(out), len(piece)) if index else 0
        for i in range(overlap):  # the end of one part fades into the start of the next
            weight = i / overlap
            at = len(out) - overlap + i
            out[at] = int(out[at] * (1 - weight) + piece[i] * weight)
        out.extend(piece[overlap:])
    return encode(out, rate)


def record(texts, voice, per_minute):
    secret = user_variable('AZURE_SPEECH_KEY')
    region = user_variable('AZURE_SPEECH_REGION')
    if not secret or not region:
        sys.exit("Set the user environment variables AZURE_SPEECH_KEY and AZURE_SPEECH_REGION first.")
    CLIPS.mkdir(parents=True, exist_ok=True)
    recorded = json.loads(RECORDED.read_text(encoding='utf-8')) if RECORDED.exists() else {}
    wanted = {clip_name(k): entry for k, entry in texts.items()}
    todo = [(name, entry) for name, entry in sorted(wanted.items())
            if recorded.get(name) != {'voice': voice, 'text': entry['record']} or not (CLIPS / name).exists()]
    print(f'{len(wanted)} texts, {len(todo)} to record with {voice}')
    pause = 60.0 / per_minute
    for index, (name, entry) in enumerate(todo, 1):
        started = time.monotonic()
        if CUT.match(entry['record']):
            clip = synthesize_cut(entry['record'], voice, region, secret)
        elif SPLIT in entry['record']:
            clip = synthesize_split(entry['record'], voice, region, secret, pause)
        elif JOIN.search(entry['record']):
            clip = synthesize_joined(entry['record'], voice, region, secret, pause)
        elif APP['close']:
            clip = synthesize_close(entry['record'], voice, region, secret)
        else:
            clip = trim(synthesize(entry['record'], voice, region, secret))
        (CLIPS / name).write_bytes(clip)
        recorded[name] = {'voice': voice, 'text': entry['record']}
        RECORDED.write_text(json.dumps(recorded, ensure_ascii=False, indent=1, sort_keys=True), encoding='utf-8')
        if index % 20 == 0 or index == len(todo):
            print(f'  {index}/{len(todo)}')
        time.sleep(max(0.0, pause - (time.monotonic() - started)))
    for stale in CLIPS.glob('he-*.mp3'):
        if stale.name not in wanted:
            stale.unlink()
            recorded.pop(stale.name, None)
    RECORDED.write_text(json.dumps(recorded, ensure_ascii=False, indent=1, sort_keys=True), encoding='utf-8')
    manifest = {'voice': voice_display_name(voice), 'clips': {k: clip_name(k) for k in sorted(texts)}}
    (CLIPS / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    size = sum(p.stat().st_size for p in CLIPS.glob('he-*.mp3'))
    print(f'Done: {len(wanted)} clips, {size / 1024 / 1024:.1f} MB in {CLIPS.relative_to(REPO)}')


def voice_display_name(voice):
    """he-IL-HilaNeural -> Hila"""
    return re.sub(r'Neural$', '', voice.split('-')[-1])


def review(texts):
    import base64
    out = HERE / 'review'
    out.mkdir(exist_ok=True)
    page_name = 'index.html' if APP is APPS['plus'] else 'mathplus.html'
    rows = []
    for k, entry in sorted(texts.items(), key=lambda item: (item[1]['sources'][0], item[0])):
        clip = CLIPS / clip_name(k)
        if clip.exists():
            src = 'data:audio/mpeg;base64,' + base64.b64encode(clip.read_bytes()).decode('ascii')
            audio = f'<audio controls preload="none" src="{src}"></audio>'
        else:
            audio = '<i>not recorded</i>'
        said = html.escape(entry['text']).replace('\n', '<br>')
        recorded = '' if key(entry['record']) == k else f'<div class="rec">recorded as: {html.escape(entry["record"])}</div>'
        english = html.escape(' / '.join(entry.get('english', [])))
        rows.append(f'<tr><td>{html.escape(", ".join(entry["sources"]))}</td><td class="en">{english}</td>'
                    f'<td dir="rtl">{said}{recorded}</td><td>{audio}</td></tr>')
    page = f"""<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Minik Hebrew clips</title>
<style>body{{font:16px system-ui;margin:16px}}td{{padding:4px 8px;border-bottom:1px solid #ccc;vertical-align:middle}}
.rec{{color:#a40;font-size:13px}}.en{{max-width:320px}}input{{font-size:16px;padding:4px;width:240px}}</style>
<h1>Minik Hebrew clips ({len(texts)})</h1>
<p><input id="q" placeholder="Search" oninput="for(const r of document.querySelectorAll('tbody tr'))r.hidden=!r.textContent.includes(this.value)"></p>
<table><tbody>{''.join(rows)}</tbody></table>"""
    (out / page_name).write_text(page, encoding='utf-8')
    print(out / page_name)


APPS = {
    'plus': {'collect': collect, 'clips': REPO / 'Resources' / 'HebrewSpeech',
             'recorded': 'recorded.json', 'texts': 'texts.tsv', 'close': False},
    'mathplus': {'collect': collect_mathplus, 'clips': REPO / 'Resources' / 'HebrewSpeechMath' / 'HebrewSpeech',
                 'recorded': 'recorded-mathplus.json', 'texts': 'texts-mathplus.tsv', 'close': True},
}
APP = APPS['plus']


def use_app(name):
    global APP, CLIPS, RECORDED
    APP = APPS[name]
    CLIPS, RECORDED = APP['clips'], HERE / APP['recorded']


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--app', choices=sorted(APPS), default='plus')
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('texts')
    recording = commands.add_parser('record')
    recording.add_argument('--voice', required=True, help='he-IL-HilaNeural or he-IL-AvriNeural')
    recording.add_argument('--per-minute', type=float, default=18, help='requests per minute (free tier allows 20)')
    commands.add_parser('trim')
    commands.add_parser('review')
    args = parser.parse_args()
    use_app(args.app)
    texts = APP['collect']()
    write_texts(texts)
    if args.command == 'texts':
        counts = {}
        for entry in texts.values():
            counts[entry['sources'][0]] = counts.get(entry['sources'][0], 0) + 1
        print(f'{len(texts)} texts: ' + ', '.join(f'{n} {s}' for s, n in sorted(counts.items())))
    elif args.command == 'record':
        record(texts, args.voice, args.per_minute)
    elif args.command == 'trim' and not APP['close']:
        before = sum(p.stat().st_size for p in CLIPS.glob('he-*.mp3'))
        for clip in CLIPS.glob('he-*.mp3'):
            clip.write_bytes(trim(clip.read_bytes()))
        after = sum(p.stat().st_size for p in CLIPS.glob('he-*.mp3'))
        print(f'{before / 1024 / 1024:.1f} MB -> {after / 1024 / 1024:.1f} MB')
    else:
        review(texts)


if __name__ == '__main__':
    main()
