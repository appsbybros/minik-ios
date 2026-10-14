"""Portable source/asset/registration checks. Does NOT replace an Xcode build or XCTest."""
from pathlib import Path
import argparse, hashlib, json, plistlib, re

parser=argparse.ArgumentParser()
parser.add_argument('--android', type=Path, default=Path(r'C:\Projects\MinikPingPong'))
args=parser.parse_args()
root=Path(__file__).resolve().parent.parent
modern=root/'Sources/ModernPong'
checks=[]
def check(condition,message):
    if not condition: raise AssertionError(message)
    checks.append(message)
read=lambda p: p.read_text(encoding='utf-8-sig')
project=read(root/'project.yml')
pong=project.split('  MinikPingPong:\n',1)[1].split('  ProductConfigurationTests:',1)[0]
check(all('product: '+name in pong for name in ['FirebaseCore','FirebaseAuth','FirebaseDatabase','GoogleMobileAds','AppStoreCommerceKit']), 'Standalone target links required native services')
check('Resources/ModernPongAssets.xcassets' in pong and 'Resources/PingPongAssets.xcassets' not in pong, 'Standalone resources contain Modern only')
check('ModernPongView(experience: .full' in read(root/'Sources/PingPongOnlyRootView.swift'), 'Standalone launches the new Full entry point')
check(not any(re.search(r'\b(PingPongView|PingPongScene|PingPongRetro\w*)\b',read(p)) for p in modern.glob('*.swift')), 'New shared Modern implementation has no legacy/80s dependencies')
plist=plistlib.loads((root/'Config/Firebase/MinikPingPong/GoogleService-Info.plist').read_bytes())
check(plist['BUNDLE_ID']=='com.appsbybros.minik.pingpong' and plist['PROJECT_ID']=='minikswish' and ':ios:' in plist['GOOGLE_APP_ID'], 'Apple Firebase registration matches the standalone bundle and project')
repository=read(modern/'MPRepository.swift')
check('database.reference().child("minikPingPong")' in repository and 'minikswish-default-rtdb.europe-west1.firebasedatabase.app' in repository, 'Firebase client uses the existing regional Ping Pong namespace')
check('MODERN_PONG_TEST_ADS: NO' in pong and 'Debug:\n          MODERN_PONG_TEST_ADS: YES' in pong, 'Test ads enabled for Debug only; Release ads disabled')
assets=[]
for catalog in (root/'Resources/ModernPongAssets.xcassets').rglob('Contents.json'):
    data=json.loads(read(catalog))
    for item in data.get('images',[]):
        if 'filename' in item:
            file=catalog.parent/item['filename'];check(file.is_file(), 'Asset exists: '+file.relative_to(root).as_posix());assets.append(file)
manifest=json.loads(read(root/'docs/modern-pong-android-assets.json'))
for item in manifest:
    dest=root/item['output'];check(dest.is_file(), 'Payload exists: '+dest.name)
    if args.android.exists():
        original=Path(item['source']);check(original.is_file() and hashlib.sha256(original.read_bytes()).hexdigest()==item['sha256'], 'Android reference unchanged: '+original.name)
names={p.stem for p in (root/'Resources/ModernPongAudio').glob('*')}
for name in set(re.findall(r'play\("([^"]+)"\)',read(modern/'MPAudio.swift')+read(modern/'MPController.swift'))): check(name in names,'Sound reference resolves: '+name)
check('cool_music2' in names, 'Guide loop asset included')
if args.android.exists():
    android=read(args.android/'app/src/main/java/com/appsbybros/minik/pingpong/Tuning.kt')
    native=read(modern/'MPTuning.swift')
    profiles=[list(map(float,re.findall(r'(?<![A-Za-z])(?:\d*\.\d+|\d+)',l.replace('..',',')))) for l in android.splitlines() if l.strip().startswith('MinikProfile(')]
    swift=[l for l in native.splitlines() if 'return MPTuning(' in l]
    for index,line in enumerate(swift):
        body=line.split('profile: MPProfile(',1)[1].replace('... ', ',').replace('...',',')
        vals=list(map(float,re.findall(r'(?<![A-Za-z])(?:\d*\.\d+|\d+)',body)))
        check(vals==profiles[index], 'Exact Android AI profile: '+['Easy','Medium','Hard','Super hard'][index])
    roster=read(args.android/'app/src/main/java/com/appsbybros/minik/pingpong/multiplayer/BotRoster.kt')
    expected=re.findall(r'character\("([^"]+)","([^"]+)","([^"]+)",([\d,]+)\)',roster)
    native=read(modern/'MPRoster.swift')
    check(len(expected)==11,'Eleven Android house players available')
    for ident,en,he,stats in expected:
        row=next(line for line in native.splitlines() if 'id: "'+ident+'"' in line)
        values=re.findall(r'(?:speed|reaction|accuracy|power|agility|forehandSkill|backhandSkill|serveSkill): (\d+)',row)
        check(values==stats.split(',') and 'english: "'+en+'"' in row and 'hebrew: "'+he+'"' in row,'Exact Android house-player identity/skills: '+ident)
    # Android 2026-09-29 gameplay changes (Beginner, house strategy, serve reliability, online fixes).
    src=args.android/'app/src/main/java/com/appsbybros/minik/pingpong'
    kt={name:read(src/name) for name in ['ModernEngine.kt','ModernGame.kt','HouseStrategy.kt','ModernTutorial.kt','ModernEvents.kt','ActorPresentation.kt','multiplayer/PongModels.kt','multiplayer/PongCodec.kt','multiplayer/MatchLink.kt','multiplayer/PlayActivity.kt','multiplayer/ControlChoice.kt']}
    physics=read(modern/'MPPhysics.swift'); engine=read(modern/'MPEngine.swift'); models=read(modern/'MPMultiplayerModels.swift')
    floats=lambda s:[float(x) for x in re.findall(r'(?<![\w.])(\d*\.\d+|\d+)(?![\w.])',s)]
    code=lambda s:'\n'.join(l.split('//',1)[0] for l in s.splitlines())
    check('STARTER, EASY, MEDIUM, HARD, BEGINNER;' in kt['ModernEngine.kt'] and 'case easy, medium, hard, superHard, beginner' in physics,'Difficulty ordinals match Android, Beginner appended as 4')
    check('val needsTwoPointLead get() = this == MEDIUM || this == HARD' in kt['ModernEngine.kt'] and 'var needsTwoPointLead: Bool { self == .hard || self == .superHard }' in physics,'Two-point lead only on Android MEDIUM/HARD')
    check('!s.level.needsTwoPointLead' in models and 'needsTwoPointLead' in kt['multiplayer/PongModels.kt'].split('fun validFinal',1)[1].split('\n',3)[2],'Room final-score validation follows the level (Beginner has no deuce)')
    check('coerceIn(0,4)' in kt['multiplayer/PongCodec.kt'] and 'min(4, max(0, c.decode(Int.self, forKey: .difficulty)))' in models,'Room difficulty decodes within Android 0...4')
    check('else->4' in kt['multiplayer/ControlChoice.kt'] and 'case 0, 1, 2: return .easy' in physics and 'case 3: return .superHard' in physics and 'default: return .beginner' in physics,'Control choice normalization matches Android ControlChoice')
    beginner_stroke=floats(re.search(r'Difficulty\.BEGINNER, Difficulty\.STARTER -> Stroke\(([^)]*)\)',kt['ModernGame.kt']).group(1))
    easy_stroke=floats(re.search(r'Difficulty\.EASY -> Stroke\(([^)]*)\)',kt['ModernGame.kt']).group(1))
    check(floats(re.search(r'case \.beginner, \.easy: childStroke = MPStroke\(([^)]*)\)',engine).group(1))==beginner_stroke==[0.1,0.4,0.5,0.62],'Beginner/Standard stroke window matches Android STARTER')
    check(floats(re.search(r'case \.medium: childStroke = MPStroke\(([^)]*)\)',engine).group(1))==easy_stroke,'Easy stroke window matches Android')
    check(re.search(r'delayedNetworkFault=it to flight!!\.striker;networkFaultTime=([\d.]+)',kt['ModernGame.kt']).group(1)=='2.0' and 'pendingFault = result; faultTime = 2.0' in engine,'Late-return grace is 2.0 s')
    check('p.distance(f.position)<=.16' in kt['ModernGame.kt'] and '(paddle ?? restingPaddle).distance(f.position) <= 0.16' in engine,'Beginner automatic contact radius matches Android')
    check('if(networked && !authoritative)' in kt['ModernGame.kt'] and 'if networked && !authoritative {' in engine and 'engine.authoritative = authority' in read(modern/'MPMatchLink.swift') and 'engine.authoritative=authority' in kt['multiplayer/MatchLink.kt'],'Only the authority awards networked points')
    check('acknowledgedLocalFlight' in kt['ModernGame.kt'] and 'if samePoint, s.rally == rally, let acknowledged = s.flight, let local = flight' in engine,'Acknowledged local flight is not rewound')
    check('serveReliability.fault(tuning.minikServeFaultProbability,random)' in kt['ModernGame.kt'] and 'serveReliability.fault(tuning.minikServeFaultProbability, random: &random)' in engine,'Minik serves use ServeReliability')
    hs=code(kt['HouseStrategy.kt'])
    ios_strategy=code(engine.split('struct MPHouseStrategy',1)[1].split('struct MPServeReliability',1)[0])
    ios_reliability=code(engine.split('struct MPServeReliability',1)[1].split('struct MPRallyVariation',1)[0].split('final class MPEngine',1)[0])
    check(set(floats(hs.split('class HouseStrategy',1)[1].split('class ServeReliability',1)[0]))==set(floats(ios_strategy)),'HouseStrategy constants match Android')
    check(set(floats(hs.split('class ServeReliability',1)[1]))==set(floats(ios_reliability)),'ServeReliability constants match Android')
    check('strategy.aim(x,random)' in kt['ModernGame.kt'] and 'strategy.aim(x, random: &random)' in engine and 'c.targetX.map' in physics,'House placement and tempo reach AI returns')
    control=kt['multiplayer/PongModels.kt'].split('fun controlTuning',1)[1].split('\n    }',1)[0]
    check('skill>=9->Difficulty.HARD;skill>=8->Difficulty.MEDIUM;skill>=7->Difficulty.EASY;else->Difficulty.STARTER' in control and 'skill >= 9 ? .superHard : skill >= 8 ? .hard : skill >= 7 ? .medium : .easy' in models,'House player AI level comes from skill')
    check(floats(re.search(r'ballBaseSpeed=([^,]*),gravity=([^,]*),bounceRestitution=([^,]*),netHeight=([^,]*),',control).group(0))==floats(re.search(r't\.ballBaseSpeed = [^\n]*',models).group(0)),'House player physics overrides match Android controlTuning')
    lessons=re.search(r'val lessons=listOf\(([^)]*)\)',kt['ModernTutorial.kt']).group(1)
    android_steps=[re.sub(r'_([a-z])',lambda m:m.group(1).upper(),n.split('.')[-1].strip().lower()) for n in lessons.split(',')]
    ios_steps=[s.strip() for s in re.search(r'enum MPTutorialStep: Int, CaseIterable \{\s*case ([^\n]*)',read(modern/'MPTutorial.swift')).group(1).split(',')]
    check(android_steps==ios_steps and len(ios_steps)==9,'Guide lessons and order match Android ('+str(len(ios_steps))+')')
    check('Fault.NET, Fault.LEFT_TABLE, Fault.FIRST_BOUNCE_OUT' in kt['ModernEvents.kt'] and '[MPFault.net, .leftTable, .firstBounceOut]' in read(modern/'MPAudio.swift'),'Failure sound only for net/out faults')
    scene=read(modern/'MPScene.swift')
    check('fun facingLeft(stroke: Stroke): Boolean = stroke.left' in kt['ActorPresentation.kt'] and 'facingLeft = stroke.left' in scene and 'walkAge' not in scene and '"step"' not in scene,'Opponent keeps swing hand; no walk cycle')
    play=kt['multiplayer/PlayActivity.kt']; view=read(modern/'ModernPongView.swift')
    check('controlValues=listOf(4,0,3)' in play and '.tag(MPLevel.beginner)' in view,'Beginner / Standard / Pro room control')
    check('Standings points per win' in play and 'Standings points per win' in view and 'winPoints: winPoints' in view,'Tournament win-points selector')
    check('tr("Remove ","הסרת ")' in play and 'model.removeHouse(row.id)' in view,'Host can remove a house player before the tournament starts')
    check('fun canFinishFriendly' in kt['multiplayer/PongModels.kt'] and 'MPRules.canFinishFriendly(s, actor: actor)' in repository,'Either friendly participant may finish the game')
    rules=args.android/'firebase-setup/merged-database-rules.json'; fragment=args.android/'firebase/pingpong.rules.fragment.json'
    # Compared without CR: this Windows checkout converts LF to CRLF (core.autocrlf) and Android keeps some rules in CRLF.
    lf=lambda p:p.read_bytes().replace(b'\r\n',b'\n')
    sha=lambda p:hashlib.sha256(lf(p)).hexdigest()
    check(sha(root/'Tests/ModernPongFirebase/rules/merged.json')==sha(rules) and sha(root/'Tests/ModernPongFirebase/rules/pingpong.json')==sha(fragment) and sha(root/'Tests/ModernPongFirebase/rules/original.json')==sha(args.android/'firebase-setup/current-database-rules.json'),'Rules snapshot matches current Android')
    check(sha(root/'Tests/ModernPongFirebase/rules/pong-team.json')==sha(args.android/'firebase/pong-team.rules.json'),'Doubles room rules (minikPongTeams) match current Android')
    rules_test=lf(args.android/'firebase/tests/rules.test.cjs')
    for a,b in [(b"'../../firebase-setup/merged-database-rules.json'",b"'../rules/merged.json'"),(b"'../../firebase-setup/current-database-rules.json'",b"'../rules/original.json'"),(b"'../pingpong.rules.fragment.json'",b"'../rules/pingpong.json'")]: rules_test=rules_test.replace(a,b)
    check(lf(root/'Tests/ModernPongFirebase/tests/rules.test.cjs')==rules_test,'Rules tests match current Android (local paths only)')
    for name in ['pong-teams.test.cjs','room-identities.test.cjs']:
        check(lf(root/'Tests/ModernPongFirebase/tests'/name)==lf(args.android/'firebase/tests'/name).replace(b"__dirname+'/../pong-team.rules.json'",b"__dirname+'/../rules/pong-team.json'"),'Doubles rules test matches current Android (local path only): '+name)
    ads_policy=read(args.android/'app/src/main/java/com/appsbybros/minik/monetization/AdPolicy.java')
    check(all(k in ads_policy for k in ['totalCompleted <= 2','2 * MINUTE','completedSinceAd >= 3 && activeSinceAd >= 5 * MINUTE','completedSinceAd >= 2 || activeSinceAd >= 210_000','Math.min(milliseconds, 5_000)','id.contains(",")']),'Android AdPolicy reference unchanged')
    # Android 2026-10-01 working tree: knockout, rally variation, controls, confetti, completion text.
    ko_kt=read(src/'multiplayer/Knockout.kt'); completion_kt=read(src/'multiplayer/CompletionText.kt'); bracket_kt=read(src/'multiplayer/KnockoutBracketView.kt')
    rally_kt=read(src/'RallyVariation.kt'); confetti_kt=read(src/'VictoryConfetti.kt'); choice_kt=kt['multiplayer/ControlChoice.kt']
    knockout=read(modern/'MPKnockout.swift'); bracket=read(modern/'MPKnockoutBracketView.swift'); scene=read(modern/'MPScene.swift')
    tutorial=read(modern/'MPTutorial.swift'); preferences=read(modern/'MPPreferences.swift'); controller=read(modern/'MPController.swift')
    check('const val MAX_PLAYERS=9' in ko_kt and 'const val MAX_ROUNDS=4' in ko_kt and 'static let maxPlayers = 9' in knockout and 'static let maxRounds = 4' in knockout,'Knockout bounds match Android (9 players, 4 rounds)')
    check('"${code}_K${round}_${pair}"' in ko_kt and '"\\(code)_K\\(round)_\\(pair)"' in knockout,'Knockout match ids match Android')
    check('"${s.code}:${s.createdAt}:$round".fold(29L){acc,c->acc*31+c.code}' in ko_kt and 'players.sorted().shuffled(Random(seed))' in ko_kt
          and '"\\(s.code):\\(s.createdAt):\\(round)".utf16.reduce(Int64(29))' in knockout and 'random.shuffled(players.sorted())' in knockout and 'struct MPKotlinRandom' in knockout,'Knockout draw seed and Kotlin XorWow shuffle match Android')
    check('"format" to s.format.name' in kt['multiplayer/PongCodec.kt'] and '"count" to r.players.size,"players" to r.players' in kt['multiplayer/PongCodec.kt']
          and 'case roundRobin = "ROUND_ROBIN", knockout = "KNOCKOUT"' in models and 'enum CodingKeys: String, CodingKey { case count, players }' in models and 'if knockout {' in models,'Knockout wire fields (format, rounds/{count, players}) match Android; round robin omits them')
    rules_fragment=read(args.android/'firebase/pingpong.rules.fragment.json'); ko_rules=read(args.android/'firebase/knockout-rules.cjs')
    check("limits=[9,5,3,2]" in ko_rules and "newData.val() == 'KNOCKOUT'" in rules_fragment and 'rounds' in rules_fragment,'Live knockout rules: per-round limits 9/5/3/2 and format KNOCKOUT')
    check(all(k in rally_kt for k in ['vertical<.01','>.09','<=.10','straight<5','vertical*.28']) and all(k in engine for k in ['vertical < 0.01','> 0.09','<= 0.10','straight < 5','vertical * 0.28']),'RallyVariation constants match Android')
    check(engine.count('rallyVariation.hit(')==4 and 'adjust: false' in engine,'Rally variation on both committed returns; remote flights only counted')
    check('(1+.35*power)' in kt['ModernEngine.kt'] and '.coerceIn(-.25,.25)' in kt['ModernEngine.kt'] and 'coerceIn(-2.0,2.0)*pace*.70' in kt['ModernEngine.kt']
          and '(1 + 0.35 * power)' in physics and 'mpClamp(-0.25, 0.25)' in physics and 'mpClamp(-2, 2) * pace * 0.70' in physics,'Forgiving tap: Standard swipe power, no sideline clamp (Android Shots.forgivingTap)')
    check('if(abs(dx)>=.012)tapAim=(dx/.085).coerceIn(-2.0,2.0)' in kt['ModernGame.kt'] and 'if abs(dx) >= 0.012 { tapAim = (dx / 0.085).mpClamp(-2, 2) }' in engine,'Beginner/Standard sideways aim matches Android updateTapGesture')
    check('((stroke.age-FOLLOW_END)/.16)' in kt['ActorPresentation.kt'] and '((age - 0.44) / 0.16)' in engine and 'stroke.recoveryBlend' in scene,'Minik FOLLOW to READY recovery cross-fade matches Android')
    check('LEFT_LEFT->.013;TutorialAction.RIGHT_LEFT->.13;TutorialAction.LEFT_MIDDLE->.055;else->.065' in kt['ModernTutorial.kt'] and 'case .leftLeft: return 0.013; case .rightLeft: return 0.13; case .leftMiddle: return 0.055; default: return 0.065' in tutorial,'Guide demonstration distances match Android')
    check('repeat(75)' in confetti_kt and 'elapsed>2.8f' in confetti_kt and 'for i in 0..<75' in bracket and 'elapsed <= 2.8' in bracket,'Victory confetti: 75 pieces for 2.8 s, as Android')
    check('fun firstCelebration' in read(src/'multiplayer/RoomBook.kt') and 'func firstCelebration' in preferences and 'enqueue' not in preferences and 'MPNotice' not in controller,'Completed rooms are not kept; routine notices retired; one celebration per room')
    check('last_completed_match' not in kt['ModernGame.kt']+read(src/'ModernActivity.kt') and 'lastCompletedMatch' not in controller,'No automatic completed-match history (Android ModernActivity)')
    check('ControlChoice.difficulty(s.difficulty)' in read(src/'multiplayer/PrivateMatchActivity.kt') and 'MPLevel.control(s.difficulty)' in controller,'Room matches play with the normalized control level')
    hebrew=re.compile(r'[֐-׿]')
    ios_text='\n'.join(read(p) for p in modern.glob('*.swift'))
    def literals(source): return [m.group(1) for m in re.finditer(r'"((?:[^"\\]|\\.)*)"',source)]
    missing=[]
    for name,source in [('Knockout.kt',ko_kt),('CompletionText.kt',completion_kt),('KnockoutBracketView.kt',bracket_kt),('ControlChoice.kt',choice_kt)]:
        for text in literals(source):
            if not hebrew.search(text): continue
            for fragment in re.split(r'\$\{[^}]*\}|\$[A-Za-z_]\w*',text):
                if len(fragment.strip())>1 and fragment not in ios_text: missing.append(name+': '+fragment)
    play_added=['שיטת הטורניר','בכל סיבוב מוגרלים זוגות מחדש. כשמספר השחקנים אי־זוגי, שחקן אחד נבחר באקראי ועולה בלי לשחק. מנצחים וממשיכים!','מתחילים: מזיזים את המחבט למקום לחבטה אוטומטית; החלקה קטנה הצידה מכוונת אותה.','רגילה: מקישים או מחליקים; החלקה מהירה מוסיפה עוצמה.','יכולת היריב נקבעת לפי שחקן הבית שתבחרו.','רמת השליטה: ','משחקים שנותרו בסיבוב הזה: ','המשחקים שלכם הסתיימו. ממתינים לשאר השחקנים לסיום הטורניר.','עץ הטורניר','החליקו לצדדים לצפייה בעץ. הזוגות מוגרלים מחדש בכל סיבוב.','לעץ הטורניר','ניצחתם במשחק!']
    play_src=read(src/'multiplayer/PlayActivity.kt')+read(src/'multiplayer/PrivateMatchActivity.kt')
    for text in play_added:
        if text not in play_src: missing.append('Android reference changed: '+text)
        elif text not in ios_text: missing.append('PlayActivity/PrivateMatchActivity: '+text)
    check(not missing,'Every new Android Hebrew text is in the iOS port'+('' if not missing else ': '+'; '.join(missing)))
if args.android.exists():
    # Android 739f2f8 (2026-10-13): ball assistance, daily journey, team play, live doubles lobby, menus and rooms.
    src=args.android/'app/src/main/java/com/appsbybros/minik/pingpong'
    reception_kt=read(src/'ReceptionAssist.kt'); camera_kt=read(src/'ReceptionCamera.kt'); reception=read(modern/'MPReception.swift')
    check(all(k in reception_kt for k in ['1-.55*strength','eta.coerceAtLeast(0.0)/1.1','eta in -.12..1.1','exp(-dt*5)','<.35']) and all(k in reception for k in ['1 - 0.55 * strength','max(eta, 0) / 1.1','eta >= -0.12, eta <= 1.1','exp(-dt * 5)','< 0.35 ? t : nil']),'Ball assistance clock matches Android ReceptionAssist')
    check(all(k in camera_kt for k in ['1+.42*amount','dt.coerceIn(0.0,.075)*4','height*.62f']) and all(k in reception for k in ['1 + 0.42 * amount','dt.mpClamp(0, 0.075) * 4','size.height * 0.62']),'Reception camera zoom matches Android ReceptionCamera')
    match_kt=read(src/'multiplayer/MatchLink.kt'); link=read(modern/'MPMatchLink.swift'); engine=read(modern/'MPEngine.swift')
    check('engine.reception.enabled&&engine.flight!=null)100 else 2000' in match_kt and 'engine.reception.enabled && engine.flight != nil ? 100 : 2000' in link and 'applyReception()' in link and 'reception.advance(dt, seat: seat, eta: eta, authority: authoritative)' in engine,'Shared slow-motion clock reaches the 1v1 engine and checkpoints (100 ms)')
    check('"receptionPreferences"' in rules_fragment and 'child("receptionPreferences")' in repository and '"version": 1, "slow": MPReceptionSettings.slow' in repository,'Reception choices are published as Android does (receptionPreferences/<uid>)')
    authority_kt=read(src/'PongTeamAuthority.kt'); room_kt=read(src/'PongTeamRoom.kt'); team=read(modern/'MPTeam.swift'); room=read(modern/'MPTeamRoom.swift')
    check('const val PROTOCOL="pong-doubles-v1"' in authority_kt and 'static let protocolName = "pong-doubles-v1"' in team and '"-lobby-v2"' in room and 'minikPongTeams' in room and 'minikPongTeams' in room_kt,'Doubles room protocol and root match Android')
    check('padStart(16,\'0\')' in room_kt and 'max(0, 16 - String(sequence).count)' in room and 'uptime-moveAt<45' in room_kt and 'uptime - moveAt < 0.045' in room,'Doubles inputs: 16-digit keys and 45 ms move throttle as Android')
    play_kt=read(src/'PongPlay.kt'); journey_kt=read(src/'PongJourney.kt'); play=read(modern/'MPPlay.swift')
    android_keys=set(re.findall(r'"(\w+)" to ',play_kt.split('fun save():Wire=',1)[1].split('companion object',1)[0]))
    save_body=play.split('func save() -> MPWire {',1)[1].split('static func restore',1)[0]
    ios_keys=set(re.findall(r'w\["(\w+)"\] = ',save_body))|set(re.findall(r'"(\w+)": ',save_body))
    check(android_keys==ios_keys,'Doubles snapshot keys match Android PongPlay.save ('+str(len(ios_keys))+')')
    android_stages=re.findall(r'PongStage\("(\w+)"',journey_kt.split('val stages=listOf(',1)[1])
    ios_stages=re.findall(r'MPStage\("(\w+)"',play.split('static let stages',1)[1].split('static func stage',1)[0])
    check(android_stages==ios_stages and len(ios_stages)==30,'Daily journey: thirty stages in Android order')
    check(all(k in play_kt for k in ['bounceRestitution=.86','.coerceIn(.09,.38)','.coerceIn(.62,.91)','(.75+successes*.022+cycle*.02).coerceAtMost(1.08)','else if(team).82 else .65','seed xor (attempts.toLong()*1000003L+rally*1009L+i*9176L)'])
          and all(k in play for k in ['t.bounceRestitution = 0.86','x.mpClamp(0.09, 0.38)','x.mpClamp(0.62, 0.91)','min(0.75 + Double(successes) * 0.022 + Double(cycle) * 0.02, 1.08)','(team ? 0.82 : 0.65)','Int64(attempts) &* 1000003 &+ Int64(rally) &* 1009 &+ Int64(i) &* 9176']),'Doubles table constants match Android PongPlay')
    android_assets=args.android/'app/src/main/assets'; art=root/'Resources/ModernPongArt'
    files=[('pong-poses/'+f.name,f) for f in sorted((android_assets/'pong-poses').iterdir())]+[('team-celebration/'+f.name,f) for f in sorted((android_assets/'team-celebration').iterdir()) if f.suffix=='.webp']
    files.append(('tournament_remove.webp',args.android/'app/src/main/res/drawable-nodpi/tournament_remove.webp'))
    check(all((art/name).is_file() and (art/name).read_bytes()==original.read_bytes() for name,original in files),'Pose atlases, team celebration and remove mark are byte-identical to Android ('+str(len(files))+' files)')
    check((art/'pong_menu_remix.mp3').stat().st_size>500_000,'Menu music converted from Android pong_menu_remix.ogg')
    ping_block=project.split('  MinikPingPong:\n',1)[1].split('\n  MinikRetroPingPong:',1)[0]
    multi_block=project.split('  MinikMultiPingPong:\n',1)[1].split('\n  MultiPongTests:',1)[0]
    math_block=project.split('  MinikMathPlus:\n',1)[1].split('\n  MinikMath:',1)[0]
    check('path: Resources/ModernPongArt\n        type: folder' in ping_block and 'ModernPongArt' not in multi_block and 'ModernPongArt' not in math_block,'Journey art bundled with the standalone app only')
    ios_all='\n'.join(read(p) for p in modern.glob('*.swift'))
    def hebrew_literals(source): return [m.group(1) for m in re.finditer(r'"((?:[^"\\]|\\.)*)"',source) if re.search(r'[֐-׿]',m.group(1))]
    missing=[]
    for name in ['PongJourney.kt','PongPlay.kt','PongRallyEnding.kt','ReceptionCamera.kt','TeamLobbyCards.kt','PongJourneyActivity.kt','PongOnlineTeamsActivity.kt','TeamVictoryView.kt','PongPracticeView.kt']:
        for text in hebrew_literals(read(src/name)):
            for fragment in re.split(r'\$\{[^}]*\}|\$[A-Za-z_]\w*',text):
                if len(fragment.strip())>1 and fragment not in ios_all: missing.append(name+': '+fragment)
    for text in ['מתחילים ולומדים','אתגר יומי','משחקים שמורים','מתקדם','הגדרות · משוב ושיתוף','משחק קבוצתי','לשמור את הטורניר?','לא לשמור','יצירת חדר','הצטרפות לחדר','שחקנים · יכולות מתוך 10','החליקו לצדדים כדי לראות את כל היכולות','המשחקים הבאים שאפשר לשחק','סיימו את המשחק הנוכחי לפני התחלת משחק נוסף.','טורנירים שמורים','עוד אין כאן משחקים. אפשר להתחיל למעלה!','לומדים משחק קבוצתי']:
        if text not in read(src/'multiplayer/PlayActivity.kt')+read(args.android/'app/src/main/res/values-iw/journey.xml'): missing.append('Android reference changed: '+text)
        elif text not in ios_all: missing.append('PlayActivity: '+text)
    check(not missing,'Every Android 739f2f8 Hebrew text is in the iOS port'+('' if not missing else ': '+'; '.join(missing)))
    check('MPKotlinRandom(seed: seed ^ mixed)' in play and 'func nextDouble()' in read(modern/'MPKnockout.swift'),'House players in doubles roll Kotlin Random(seed) exactly as Android')
controller=read(modern/'MPController.swift'); view=read(modern/'ModernPongView.swift'); ads=read(modern/'MPAds.swift')
check('UserDefaults.standard.bool(forKey: "MinikOfflineSmoke")' in controller and 'else if MPController.offlineSmoke { repo = MPLocalRepository() }' in controller,'CI offline smoke launch never uses Firebase')
check('if !practice && !skipGuide && !guideOffered' in controller and 'didSet { preferences.skipGuide = skipGuide }' in controller,'Guide opens automatically unless hidden')
check('ParentalGateView(onCancel:' in view and 'if commerceUnlocked { commerceSheet }' in view and view.count('commerceSheet')==2,'Purchase, restore and code redemption only behind the grown-up gate')
check('guard experience == .full, ProductVariant.current == .minikPingPong' in ads and 'MinikAdsConfiguration.load(product: .minikPingPong).providerConfiguration' in ads,'Modern ads: standalone Full only; production IDs from MinikAdsConfiguration')
check(all(k in ads for k in ['ageRestrictedTreatment = .child','GADMaxAdContentRating.general','publisherPrivacyPersonalizationState = .disabled','await MobileAds.shared.start()']),'Modern ad requests are child-directed, G-rated and non-personalized')
check(re.search(r'total > 2[\s\S]*120_000[\s\S]*300_000[\s\S]*210_000',ads) is not None and 'id.count <= 200, !id.contains(",")' in ads,'Modern ad cadence matches Android AdPolicy')
tests=read(root/'Tests/ProductConfigurationTests/ModernPongParityTests.swift')+read(root/'Tests/ProductConfigurationTests/ModernPongTeamsTests.swift')
test_count=len(re.findall(r'func test\w+\(',tests))
check(test_count>=20,'Focused XCTest cases registered: '+str(test_count))
print(json.dumps({'status':'PASS','source_asset_config_checks':len(checks),'swift_tests_authored_not_executed':test_count,'asset_bytes':sum(p.stat().st_size for p in assets),'checks':checks},ensure_ascii=True,indent=2))
