"""Offline provenance and iOS host-boundary checks. No Apple toolchain or device required."""
from pathlib import Path
import hashlib
import json
import re

root = Path(__file__).resolve().parents[1]
web = root / 'Resources/RetroPong'
checks = 0
def check(ok, message):
    global checks
    if not ok: raise AssertionError(message)
    checks += 1
def text(name): return (root / name).read_text(encoding='utf-8-sig')
def digest(file, mode='bytes'):
    data = file.read_bytes()
    if mode == 'lf-text': data = data.replace(b'\r\n', b'\n')
    return hashlib.sha256(data).hexdigest()

items = json.loads(text('docs/retro-pong-android-provenance.json'))
for item in items:
    check(digest(root / item['output'], item.get('outputHashMode', 'bytes')) == item['outputSHA256'], 'Payload differs from recorded Android import: '+item['output'])
    # Android is optional on other development hosts. When present, verify it was left untouched.
    source = Path(item['source'])
    if source.is_file(): check(digest(source) == item['sourceSHA256'], 'Android source changed since import: '+str(source))

for file in web.rglob('*'):
    if file.suffix not in ['.html', '.css', '.js'] or file.name == 'minik-audio-bank.js': continue
    for asset in re.findall(r'(?:src=["\']|url\(["\']?)(assets/[^"\'\s)<>]+)', file.read_text(encoding='utf-8-sig')):
        if '${' not in asset: check((web / asset).is_file(), 'Missing asset: '+asset)

project = text('project.yml')
targets = project.split('\nschemes:\n')[0]
retro = re.split(r'\n  [A-Za-z]+:\n', targets.split('  MinikRetroPingPong:\n', 1)[1], maxsplit=1)[0]
# The original iOS Math app, now Minik Math Plus, hosts both Ping Pong games.
math = targets.split('  MinikMathPlus:\n', 1)[1].split('  MinikMath:\n', 1)[0]
check('type: folder' in retro and 'Resources/RetroPong' in retro, 'Standalone must preserve WebKit relative paths')
check('Resources/RetroPong' in math and 'Resources/ModernPongAssets.xcassets' in math, 'Both current games need their resources in Math')
check('com.appsbybros.minik.bouncelearn' in retro, 'Separate standalone app identity missing')
check('MINIK_RETRO_PING_PONG' in retro, 'Standalone launch condition missing')
check('FirebaseApple' not in retro and 'GoogleMobileAds' in retro and 'ca-app-pub-6728099379581161~9515819906' in retro, 'Bounce has no Firebase and uses its own AdMob app, like Android Bounce')
check('MinikModernPongTestAds' not in retro, 'Retro cannot opt into Modern ads')
app = text('Sources/MinikApp.swift')
check('#if MINIK_RETRO_PING_PONG\n            BounceRootView()' in app, 'Standalone must launch the Bounce host')
bounce = text('Sources/RetroPong/BounceRootView.swift')
check('RetroPongView(onMatchFinished:' in bounce and 'ParentalGateView(' in bounce and '.bounceMatch' in bounce, 'Standalone Bounce needs ads after a finished game and a gated parents sheet')
hub = text('Sources/MinikActivityHubView.swift')
check(hub.count('MathPingPongChooser(') == 2 and hub.count('onCompletedMatch: { recordLanguageAdOpportunity(.mathRound) }') == 2, 'Both Math routes must use updated chooser')
chooser = text('Sources/RetroPong/MathPingPongChooser.swift')
check('ModernPongView(experience: .simple' in chooser and 'case .retro: RetroPongView(onExit: onExit, onMatchFinished: { done in onCompletedMatch(); done() })' in chooser, 'Math integration changed')
host = text('Sources/RetroPong/RetroPongView.swift')
check('experience:' not in host and 'Commerce' not in host and 'AdMob' not in host, 'Retro must have one feature set and no ads hook')
for contract in ['loadFileURL', 'allowingReadAccessTo: directory', '.atDocumentStart', 'isMainFrame', 'RetroPongNavigation.isBundled', 'removeScriptMessageHandler', 'func dismantleUIView', 'webViewWebContentProcessDidTerminate', 'storage.bootstrap', 'numberOfLoops = -1']:
    check(contract in host, 'Native host contract missing: '+contract)
# Android Bounce 506490e: the family messages. Ad-break card and idle-setup reminder in the
# standalone app only; Math's Bounce has no parents link, so it never asks for the reminder.
check('FamilyOverlay()' in bounce and 'family: familyBreak.adBreak()' in bounce and 'onMenuIdle: menuIdle' in bounce
      and 'showMoreApps(gate: nil)' in bounce and 'FamilyMessages.shared.remind(' in bounce, 'Standalone Bounce must host the family messages like Android Bounce')
check('MinikFamilyCatalogKey: bounce' in retro and 'Family/minik-family-catalog.json' in retro and 'Family/FamilyArt.xcassets' in retro, 'Bounce needs its family catalogue key, catalogue and art')
check('case "menuIdle": if active { onMenuIdle?() }' in host, 'Native host must forward the idle-setup signal')
ios_host = text('Resources/RetroPong/ios-host.js')
check('send({type: "menuIdle"})' in ios_host and 'menuRoot = parent;' in ios_host, 'ios-host.js must signal the idle setup only once the parents link exists')
# Android Bounce 4f38dd5: rating, sharing and feedback only on the gated parents page; the
# "For parents" link sits in the measured gap above Start (or under the title).
support = bounce.split('@ViewBuilder private var parentsSheet', 1)[1].split('ParentalGateView(', 1)[0]
check('supportSection' in support and 'MinikAppFeedback.requestReview()' in bounce and 'MinikShareSheet(text:' in bounce
      and 'MinikAppFeedback.feedbackAddress' in bounce and 'UIPasteboard.general.string' in bounce, 'Bounce parents page needs rate, share and feedback behind the gate')
check('document.createElement("a")' in ios_host and '".pong-setup-actions"' in ios_host and 'gridRow: "2"' in ios_host, 'ios-host.js must place the parents link like Android Bounce 4f38dd5')
index = text('Resources/RetroPong/index.html')
check('maze-sky.css' in index and index.index('maze-sky.css') < index.index('ios-host.css'), 'ios-host.css must stay the last stylesheet, after Android maze-sky.css')
check('frame-src \'none\'' in text('Resources/RetroPong/index.html'), 'Offline CSP missing')
check('connect-src \'none\'' in text('Resources/RetroPong/index.html'), 'Offline network boundary missing')
for asset in ['minik_kick', 'minik_kick2', 'success_sound', 'success_in_a_raw_sound', 'failure_answer_sound', 'failure_sound', 'balloon_explode', 'ball_hit', 'car_hit', 'train_hit', 'train_horn', 'game_start']:
    check((web / ('assets/audio/'+asset+'.mp3')).is_file(), 'Missing sound: '+asset)
print(json.dumps({'checks_passed':checks,'payload_entries':len(items),'native_build_verified':False}))
