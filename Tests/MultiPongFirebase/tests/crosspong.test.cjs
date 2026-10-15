// Minik Cross Pong rules (minikCrossPong/) in the local RTDB emulator. The helpers below build rooms exactly
// as PongCodec/PongRules/GroupTournament/Knockout write them (seat lists, N-player scores and placements,
// group tables, walkovers, goals, tie-breaks and elimination duels). Emulator only: never production.
const {before,after,beforeEach,test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const {initializeTestEnvironment,assertSucceeds,assertFails}=require('@firebase/rules-unit-testing');
const NS='minikCrossPong';
const mergedPath=path.resolve(__dirname,'../rules/merged.json');
let env;
before(async()=>{
  const [host,port]=(process.env.FIREBASE_DATABASE_EMULATOR_HOST||'').split(':');
  assert.ok(host==='127.0.0.1'&&Number(port)>0,'Local emulator required (emulators:exec sets it); never use production');
  env=await initializeTestEnvironment({projectId:'demo-minik-crosspong',database:{host,port:Number(port),rules:fs.readFileSync(mergedPath,'utf8')}});
});
after(async()=>{if(env)await env.cleanup()});
beforeEach(async()=>{await env.clearDatabase()});
const db=uid=>(uid?env.authenticatedContext(uid):env.unauthenticatedContext()).database();
const clone=o=>structuredClone(o);
const admin=fn=>env.withSecurityRulesDisabled(c=>fn(c.database()));
// withSecurityRulesDisabled resolves to nothing; keep the value from inside the callback.
const read=async p=>{let value;await admin(async d=>{value=(await d.ref(p).once('value')).val()});return value};
const seed=async(kind,r)=>{const p=`${NS}/${kind}/${r.code}`;await admin(d=>d.ref(p).set(r));return p};
const change=async(uid,p,fn)=>{const current=await read(p);return db(uid).ref(p).set(fn(clone(current))??current)};
const reserve=(uid,kind,code,slot=0)=>assertSucceeds(db(uid).ref(`${NS}/openSlots/${uid}/${kind}/${slot}`).set(code));
const terminal=m=>m.phase==='FINISHED'||m.phase==='CANCELLED';
const list=x=>Array.isArray(x)?x:Object.keys(x||{}).sort((a,b)=>a-b).map(k=>x[k]);

// ---- PongCodec/PongRules mirror ----
const characters=['kyra','flare','mia','gaya','amber','comet','june','miniko','coach67'];
const identity=id=>({id,name:id.startsWith('bot_')?'House':id,avatar:0});
const botProfile=characterId=>({speed:8,reaction:8,accuracy:8,power:8,agility:8,characterId,forehandSkill:8,backhandSkill:8,serveSkill:8});
// gameMode is written only for ELIMINATION, advance only for 1 (PongCodec.session).
function room(kind,{ids=['alice'],code='ABCDEF',tableSize=2,capacity,format,legs=1,difficulty=0,target=7,gameMode,advance}={}){
  const friendly=kind==='friendlyRooms';
  const r={code,kind:friendly?'FRIENDLY':'TOURNAMENT',host:ids[0],capacity:capacity??(friendly?tableSize:ids.length),tableSize,legs,winPoints:3,lossPoints:0,
    difficulty,target,participants:{},roster:[],rosterSize:0,state:'WAITING',createdAt:Date.now(),lastActivityAt:Date.now()};
  if(format)r.format=format;
  if(gameMode!==undefined)r.gameMode=gameMode;
  if(advance!==undefined)r.advance=advance;
  for(const id of ids)add(r,id);
  return r;
}
// House players cycle through the characters (a tournament may repeat one; a friendly table seats at most 3).
function add(r,id,seat){
  const bots=Object.values(r.participants).filter(p=>p.bot).length;
  r.participants[id]={identity:identity(id),...(id.startsWith('bot_')?{bot:botProfile(characters[bots%characters.length])}:{})};
  r.roster=Object.keys(r.participants).sort();r.rosterSize=r.roster.length;
  if(r.kind==='FRIENDLY'){r.seats??={};const taken=Object.values(r.seats);r.seats[id]=seat??[0,1,2,3].find(s=>!taken.includes(s));}
  return r;
}
const seedOf=id=>[...id].reduce((a,ch)=>(a*31+ch.charCodeAt(0))%1000000007,17);
// PongRules.fixtureTarget / eliminates: a tie-break plays to one point; an ELIMINATION table of 3/4 ends with two left.
const fixtureTarget=(r,m)=>m.goal==='TIEBREAK'?1:r.target;
const eliminates=(r,m)=>m.matchSize>2&&(m.goal==='TOP_TWO'||!m.goal&&r.gameMode==='ELIMINATION');
function simulate(r,m){
  const t=fixtureTarget(r,m);m.phase='FINISHED';delete m.ready;
  m.scores=eliminates(r,m)?m.players.map((_,k)=>k<2?t-1-k:0):m.matchSize===2?[t,Math.max(0,t-3)]:m.players.map((_,k)=>k?Math.max(0,t-1-k):t);
  m.placement=[...m.players];m.winner=m.players[0];return m;
}
function fixture(r,id,players,goal){
  const humans=players.filter(p=>!r.participants[p]?.bot).sort();   // an outsider counts as a human here
  const m={id,players:[...players],matchSize:players.length,seed:seedOf(id),phase:'WAITING',scores:players.map(()=>0),winner:'',starts:0,authorityUid:humans[0]||r.host,...(goal?{goal}:{})};
  return humans.length?m:simulate(r,m);
}
// An ELIMINATION table without a goal (one winner) is decided by the classic duel of its two survivors, created with its result.
const needsDuel=(r,m)=>m.phase==='FINISHED'&&m.matchSize>=3&&!m.goal&&r.gameMode==='ELIMINATION';
function duels(r){for(const m of Object.values(r.matches||{}))if(needsDuel(r,m)&&!r.matches[`${m.id}_D`])r.matches[`${m.id}_D`]=fixture(r,`${m.id}_D`,list(m.placement).slice(0,2));return r}
const complete=r=>{duels(r);r.state=Object.values(r.matches).every(terminal)?'FINISHED':'ACTIVE';return r};
function friendlyStart(r){const seated=Object.entries(r.seats).sort((a,b)=>a[1]-b[1]).map(e=>e[0]),id=`${r.code}_0_0_1`;r.matches={[id]:fixture(r,id,seated)};return complete(r)}
function pairSchedule(r){
  const ids=Object.keys(r.participants).sort();r.matches={};
  for(let leg=0;leg<r.legs;leg++)for(let i=0;i<ids.length;i++)for(let j=i+1;j<ids.length;j++){const id=`${r.code}_${leg}_${i}_${j}`;r.matches[id]=fixture(r,id,leg?[ids[j],ids[i]]:[ids[i],ids[j]])}
  return complete(r);
}
// GroupTournament.design table counts; the tables here are rotations of the sorted roster (the rules
// check count, size, membership and the leg rotation, not the seeded draw).
const TABLES={3:{3:1,4:1},4:{3:4,4:1},5:{3:5,4:3},6:{3:6,4:3},7:{3:7,4:5},8:{3:11,4:6}};
function groupSchedule(r){
  const ids=Object.keys(r.participants).sort(),n=ids.length,k=Math.min(r.tableSize,n);r.matches={};
  for(let leg=0;leg<r.legs;leg++)for(let t=0;t<TABLES[n][r.tableSize];t++){
    const table=Array.from({length:k},(_,j)=>ids[(t+j)%n]),turn=leg%k,id=`${r.code}_T${leg}_${t}`;
    r.matches[id]=fixture(r,id,[...table.slice(turn),...table.slice(0,turn)]);
  }
  return complete(r);
}

// ---- Knockout mirror (Knockout.draw/settle/through, GroupTournament.split) ----
// split: 2..4 one table, 5 -> 3+2, from 6 on only tables of 3 and 4, as many of the preferred size as possible.
function split(n,size){
  if(n<=4)return n>=2?[n]:[];
  if(n===5)return [3,2];
  let best;for(let f=0;f<=Math.floor(n/4);f++)if((n-4*f)%3===0){const o=[...Array(f).fill(4),...Array((n-4*f)/3).fill(3)];if(!best||o.filter(x=>x===size).length>best.filter(x=>x===size).length)best=o}
  return best;
}
const grouped=r=>r.tableSize>=3;
const perTable=r=>r.advance??2;
// A table no larger than the number going through is a walkover; the final (2..4 players) is one table.
function draw(r,ids,round){
  r.rounds??={};r.matches??={};r.state='ACTIVE';
  if(grouped(r)){
    const final=ids.length<=4;let at=0;
    const groups=split(ids.length,r.tableSize).map(size=>ids.slice(at,at+=size));
    const walkovers=groups.filter(g=>!final&&g.length<=perTable(r)),tables=groups.filter(g=>final||g.length>perTable(r));
    const goal=!final&&r.gameMode==='ELIMINATION'&&perTable(r)===2?'TOP_TWO':undefined;
    r.rounds[round]={count:ids.length,players:[...tables.flat(),...walkovers.flat()],tables,...(walkovers.length?{walkovers}:{})};
    tables.forEach((t,i)=>{const id=`${r.code}_K${round}_${i}`;r.matches[id]=fixture(r,id,t,goal)});
  } else {
    r.rounds[round]={count:ids.length,players:[...ids]};
    for(let i=0;i+1<ids.length;i+=2){const id=`${r.code}_K${round}_${i/2}`;r.matches[id]=fixture(r,id,[ids[i],ids[i+1]])}
  }
  return r;
}
const lastRound=r=>Math.max(...Object.keys(r.rounds).map(Number));
const tablesOf=(r,round)=>{const d=r.rounds[round];if(grouped(r))return list(d.tables).map(list);const p=list(d.players),out=[];for(let i=0;i+1<p.length;i+=2)out.push([p[i],p[i+1]]);return out};
const tableIds=(r,round)=>tablesOf(r,round).map((_,i)=>`${r.code}_K${round}_${i}`);
const resting=(r,round)=>{const d=r.rounds[round];return grouped(r)?[...list(d.byes),...list(d.walkovers).flatMap(list)]:d.count%2?[list(d.players)[d.count-1]]:[]};
const isFinal=(r,round)=>tablesOf(r,round).length===1&&!resting(r,round).length;
const eligible=(r,id)=>id&&r.participants[id]&&!r.departed?.[id];
const scoreIn=(m,p)=>list(m.scores)[list(m.players).indexOf(p)];
function resolve(r,m){
  if(!m||terminal(m))return;
  if(list(m.players).some(p=>!eligible(r,p))){m.phase='CANCELLED';delete m.ready;m.winner=list(m.players).find(p=>eligible(r,p))||''}
  else if(list(m.players).every(p=>r.participants[p].bot))simulate(r,m);
}
function tied(r,round,m){
  if(!grouped(r)||isFinal(r,round)||m.phase!=='FINISHED'||m.goal||m.matchSize<3||r.gameMode||perTable(r)<2)return [];
  const rest=list(m.players).filter(p=>p!==m.winner),best=Math.max(...rest.map(p=>scoreIn(m,p)));
  const tie=rest.filter(p=>scoreIn(m,p)===best);return tie.length>1?tie:[];
}
function through(r,round,m){
  if(!grouped(r))return [m.winner];
  if(m.phase==='CANCELLED')return list(m.players);
  const duel=r.matches[`${m.id}_D`];
  if(duel)return duel.phase==='FINISHED'?[duel.winner]:duel.phase==='CANCELLED'?list(duel.players):[];
  const first=list(m.placement).length?list(m.placement):[m.winner];
  if(isFinal(r,round))return first.slice(0,1);
  if(m.goal==='TOP_TWO')return first.slice(0,2);
  if(!r.gameMode&&perTable(r)===2&&m.matchSize>2){
    if(!tied(r,round,m).length){const rest=list(m.players).filter(p=>p!==m.winner);return [first[0],rest.reduce((a,b)=>scoreIn(m,b)>scoreIn(m,a)?b:a)]}
    const tb=r.matches[`${m.id}_T`];
    return [first[0],...(!tb?[]:tb.phase==='FINISHED'?[tb.winner]:tb.phase==='CANCELLED'?list(tb.players):[])];
  }
  return first.slice(0,1);
}
function advancing(r,round){
  const out=tableIds(r,round).map(id=>r.matches[id]).filter(m=>m&&terminal(m)).flatMap(m=>through(r,round,m));
  return [...new Set([...out,...resting(r,round)])].filter(id=>eligible(r,id));
}
const roundFixtures=(r,round)=>tableIds(r,round).flatMap(id=>[r.matches[id],r.matches[`${id}_T`],r.matches[`${id}_D`]]).filter(Boolean);
// Finish house tables, add duels and tie-breaks in the same write, redraw only after the whole round is decided.
function settle(r){
  for(let guard=0;guard<=16;guard++){
    const round=lastRound(r),ids=tableIds(r,round);
    for(const id of ids)resolve(r,r.matches[id]);
    for(const id of ids){
      const m=r.matches[id];
      if(needsDuel(r,m)&&!r.matches[`${id}_D`])r.matches[`${id}_D`]=fixture(r,`${id}_D`,list(m.placement).slice(0,2));
      const tie=tied(r,round,m);if(tie.length&&!r.matches[`${id}_T`])r.matches[`${id}_T`]=fixture(r,`${id}_T`,tie,'TIEBREAK');
    }
    for(const id of ids)for(const x of ['_T','_D'])resolve(r,r.matches[id+x]);
    if(roundFixtures(r,round).some(m=>!terminal(m))){r.state='ACTIVE';return r}
    const next=advancing(r,round);
    if(next.length<=1){r.state='FINISHED';return r}
    draw(r,next.slice().reverse(),round+1);  // any order: the real draw is seeded
  }
  throw new Error('the knockout exceeded its rounds');
}
const start=r=>r.format==='KNOCKOUT'?settle(draw(r,Object.keys(r.participants).sort().reverse(),0)):r.kind==='FRIENDLY'?friendlyStart(r):r.tableSize>=3?groupSchedule(r):pairSchedule(r);
const ready=(r,id,uid)=>{const m=r.matches[id];m.ready={...m.ready,[uid]:true};m.phase='READY';return r};
const playing=(r,id)=>{const m=r.matches[id];m.phase='PLAYING';m.starts=1;delete m.ready;return r};
const play=(r,id)=>{for(const uid of list(r.matches[id].players))if(!r.participants[uid].bot)ready(r,id,uid);return playing(r,id)};
// Placement: by score, seat order on ties (winner takes all, pairs, tie-breaks) unless given (ELIMINATION).
function finish(r,id,scores,placement){
  const m=r.matches[id],players=list(m.players);Object.assign(m,{phase:'FINISHED',scores});delete m.ready;
  m.placement=placement??players.map((p,k)=>[p,scores[k],k]).sort((a,b)=>b[1]-a[1]||a[2]-b[2]).map(x=>x[0]);m.winner=m.placement[0];
  return r.format==='KNOCKOUT'?settle(r):complete(r);
}
function leave(r,uid){
  const peer=Object.keys(r.participants).sort().find(p=>p!==uid&&!r.participants[p].bot&&!r.departed?.[p]&&Object.keys(r.connections?.[p]||{}).length);
  if(r.host===uid)r.host=peer;
  if(r.connections)delete r.connections[uid];
  if(r.state==='WAITING'){delete r.participants[uid];r.roster=Object.keys(r.participants).sort();r.rosterSize=r.roster.length;return r}
  r.departed={...r.departed,[uid]:true};
  for(const m of Object.values(r.matches))if(list(m.players).every(p=>r.participants[p].bot))m.authorityUid=r.host;
  if(r.format==='KNOCKOUT')return settle(r);
  for(const m of Object.values(r.matches))if(list(m.players).includes(uid)&&!terminal(m)){m.phase='CANCELLED';delete m.ready}
  return complete(r);
}
const online=(r,...uids)=>{r.connections={...r.connections,...Object.fromEntries(uids.map(u=>[u,{0:true}]))};return r};
const others=(r,...ids)=>{const out=clone(r);for(const id of ids)delete out.matches[id];return out};

// ---- isolation and structure ----
// iOS mirror (5c1aa4d): Android's generate-rules.cjs now also merges the separate team root (minikCrossTeams, from
// cross-team.json); Android's own copy of this test was not updated for it. Both roots are excluded here.
// Android cae4ee6 regenerated the merged candidate from the live rules (rules/current.json and rules/merged.json are its
// copies), so minikCrossPong has its receptionPreferences and minikCrossTeams equals cross-team.json again.
const TEAMS='minikCrossTeams';
test('merge adds only minikCrossPong and minikCrossTeams to the live rules; every other subtree is byte-for-byte unchanged',()=>{
  const current=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../rules/current.json'),'utf8'));
  const merged=JSON.parse(fs.readFileSync(mergedPath,'utf8'));
  const fragment=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../rules/crosspong.fragment.json'),'utf8'));
  const teams=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../rules/cross-team.json'),'utf8'));
  assert.equal(merged.rules['.read'],false);assert.equal(merged.rules['.write'],false);
  assert.deepEqual(merged.rules[NS],fragment.rules[NS]);
  assert.deepEqual(merged.rules[TEAMS],teams.rules[TEAMS]);
  assert.ok(current.rules.minikPingPong&&current.rules.tripleShot,'the live rules hold the original apps');
  for(const key of Object.keys(current.rules))if(key!==NS&&key!==TEAMS)assert.equal(JSON.stringify(merged.rules[key]),JSON.stringify(current.rules[key]),key);
  assert.deepEqual(Object.keys(merged.rules).filter(k=>k!==NS&&k!==TEAMS),Object.keys(current.rules).filter(k=>k!==NS&&k!==TEAMS));
  assert.equal(merged.rules[NS]['.read'],false);assert.equal(merged.rules[NS]['.write'],false);
});
test('collection scans, unknown children and monetization are denied even to signed-in users',async()=>{
  for(const p of [undefined,NS,`${NS}/profiles`,`${NS}/nicknames`,`${NS}/openSlots`,`${NS}/friendlyRooms`,`${NS}/tournaments`,`${NS}/live`,`${NS}/monetization`,`${NS}/leaderboard`])
    await assertFails(db('alice').ref(p).once('value'));
  for(const p of [`${NS}/leaderboard/alice`,`${NS}/monetization/codes/free`,`${NS}/other`])await assertFails(db('alice').ref(p).set({enabled:true}));
  await assertFails(db().ref(`${NS}/profiles/alice`).once('value'));
  const p=await seed('friendlyRooms',room('friendlyRooms'));
  await assertSucceeds(db('bob').ref(p).once('value')); // a known code is the read capability, as in Ping Pong
  await assertFails(db().ref(p).once('value'));
});
test('profiles need an own reserved nickname; impersonation and invalid values are rejected',async()=>{
  await assertSucceeds(db('alice').ref(`${NS}/nicknames/GreenFrog`).set('alice'));
  await assertFails(db('bob').ref(`${NS}/nicknames/GreenFrog`).set('bob'));
  for(const name of ['FreeText','GreenFrog0','<Flare>'])await assertFails(db('alice').ref(`${NS}/nicknames/${name}`).set('alice'));
  await assertSucceeds(db('alice').ref(`${NS}/nicknames/סהר בקיץ`).set('alice'));
  await assertSucceeds(db('alice').ref(`${NS}/profiles/alice`).set({...identity('alice'),name:'GreenFrog',characterId:'june',updatedAt:1}));
  await assertFails(db('bob').ref(`${NS}/profiles/alice`).set({...identity('alice'),name:'GreenFrog'}));
  for(const bad of [{name:'BlueFox'},{name:''},{id:'bob'},{avatar:6},{characterId:'nobody'}])
    await assertFails(db('alice').ref(`${NS}/profiles/alice`).set({...identity('alice'),name:'GreenFrog',...bad}));
});
test('three open slots per category; no bypass, no foreign reads',async()=>{
  for(const [slot,code] of ['ABCDEF','BCDEFG','CDEFGH'].entries()){
    await reserve('alice','friendlyRooms',code,slot);
    await assertSucceeds(db('alice').ref(`${NS}/friendlyRooms/${code}`).set(room('friendlyRooms',{code,tableSize:3})));
  }
  await assertFails(db('alice').ref(`${NS}/openSlots/alice/friendlyRooms/3`).set('DEFGHJ'));
  await assertFails(db('alice').ref(`${NS}/openSlots/alice/friendlyRooms/0`).set('DEFGHJ'));
  await assertFails(db('bob').ref(`${NS}/openSlots/alice`).once('value'));
  await assertFails(db('alice').ref(`${NS}/friendlyRooms/DEFGHJ`).set(room('friendlyRooms',{code:'DEFGHJ',tableSize:3})));
  await assertSucceeds(db('alice').ref(`${NS}/friendlyRooms/ABCDEF`).remove());
  await assertSucceeds(db('alice').ref(`${NS}/openSlots/alice/friendlyRooms/0`).set('DEFGHJ'));
});

// ---- friendly tables of 3 and 4 ----
test('friendly 3-seat room: create, join, seats, house player, start, Ready, start once, authority result',async()=>{
  const kind='friendlyRooms',p=`${NS}/${kind}/ABCDEF`,m='ABCDEF_0_0_1';
  const created=room(kind,{tableSize:3});
  await assertFails(db('alice').ref(p).set(created));                       // no reservation yet
  await reserve('alice',kind,'ABCDEF');
  for(const bad of [{capacity:4},{tableSize:5,capacity:5},{tableSize:1,capacity:1},{format:'KNOCKOUT'},{target:8},{seats:{alice:3}}])
    await assertFails(db('alice').ref(p).set({...clone(created),...bad}));
  await assertSucceeds(db('alice').ref(p).set(created));
  await reserve('bob',kind,'ABCDEF');
  await assertFails(change('bob',p,r=>add(r,'mallory')));                    // joining as somebody else
  await assertFails(change('bob',p,r=>add(r,'bob',0)));                      // seat taken
  await assertSucceeds(change('bob',p,r=>add(r,'bob')));
  await assertFails(change('alice',p,r=>{r.seats.bob=2;return r}));          // nobody moves another player
  await assertFails(change('bob',p,r=>{r.seats.bob=0;return r}));           // nor takes a used seat
  await assertSucceeds(change('bob',p,r=>{r.seats.bob=2;return r}));        // own free seat
  await assertFails(change('bob',p,r=>add(r,'bot_one',1)));                  // only the host adds house players
  await assertFails(change('alice',p,r=>{add(r,'bot_one',2);r.seats.bob=1;return r}));   // nor does the host
  await assertSucceeds(change('alice',p,r=>add(r,'bot_one',1)));
  await reserve('carol',kind,'ABCDEF');
  await assertFails(change('carol',p,r=>add(r,'carol',3)));                 // full table
  await assertFails(change('alice',p,r=>{delete r.seats.bob;return r}));
  const wrongOrder=friendlyStart(await read(p));wrongOrder.matches[m].players.reverse();
  await assertFails(db('alice').ref(p).set(wrongOrder));
  await assertFails(change('bob',p,friendlyStart));                          // the host starts
  await assertSucceeds(change('alice',p,friendlyStart));
  const started=await read(p);
  assert.deepEqual(started.matches[m].players,['alice','bot_one','bob']);assert.equal(started.matches[m].authorityUid,'alice');
  await assertFails(change('alice',p,r=>{r.seats.alice=1;r.seats.bot_one=0;return r}));  // seats are fixed after the start
  await assertSucceeds(change('alice',p,r=>ready(r,m,'alice')));
  await assertFails(change('alice',p,r=>ready(r,m,'bob')));                  // own Ready only
  await assertFails(change('alice',p,r=>ready(r,m,'bot_one')));
  await assertSucceeds(change('bob',p,r=>ready(r,m,'bob')));
  await assertFails(change('alice',p,r=>playing(r,m)));                      // nobody connected
  for(const uid of ['alice','bob'])await assertSucceeds(db(uid).ref(`${p}/connections/${uid}/0`).set(true));
  await assertSucceeds(change('bob',p,r=>playing(r,m)));
  await assertFails(change('alice',p,r=>{r.matches[m].starts=2;return r}));   // start once
  await assertFails(change('alice',p,r=>{r.matches[m].phase='READY';r.matches[m].ready={alice:true};r.matches[m].starts=0;return r}));
  await assertFails(change('bob',p,r=>finish(r,m,[5,0,7])));                 // not the authority
  for(const scores of [[7,7,0],[8,0,6],[6,5,0],[7,-1,0],[7,1.5,0],[7,0]]) await assertFails(change('alice',p,r=>finish(r,m,scores)));
  await assertFails(change('alice',p,r=>{finish(r,m,[5,0,7]);r.matches[m].placement=['bob','bot_one','alice'];return r}));   // ordered by score
  await assertFails(change('alice',p,r=>{finish(r,m,[5,0,7]);r.matches[m].placement=['bob','alice','alice'];return r}));     // a permutation
  await assertFails(change('alice',p,r=>{finish(r,m,[5,0,7]);r.matches[m].winner='alice';return r}));
  await assertFails(change('alice',p,r=>{finish(r,m,[5,0,7]);r.matches[m].placement.pop();return r}));
  await assertFails(change('alice',p,r=>{finish(r,m,[5,0,7]);r.matches[m].goal='TIEBREAK';return r}));     // goals belong to knockouts
  await assertSucceeds(change('alice',p,r=>finish(r,m,[5,0,7])));
  const done=await read(p);assert.equal(done.state,'FINISHED');assert.deepEqual(done.matches[m].placement,['bob','alice','bot_one']);
  assert.equal(done.matches[`${m}_D`],undefined);                            // winner takes all: no duel
  await assertSucceeds(db('alice').ref(p).set(done));                        // an idempotent retry
  await assertFails(change('alice',p,r=>{r.matches[m].scores[1]=1;return r}));                      // immutable result
  await assertFails(change('alice',p,r=>{r.matches[m].placement=['bob','bot_one','alice'];return r}));
  await assertFails(db('alice').ref(`${p}/matches/${m}`).remove());
  await assertFails(db('eve').ref(p).remove());
  await assertSucceeds(db('bob').ref(p).remove());                           // Finish by any human member
});
test('friendly 4-seat room of humans: Ready needs every human connected; only the smallest uid finishes',async()=>{
  const kind='friendlyRooms',m='ABCDEF_0_0_1';
  let r=room(kind,{tableSize:4,difficulty:3,target:11});for(const id of ['dave','bob','carol'])add(r,id);
  const p=await seed(kind,r);
  await assertSucceeds(change('alice',p,friendlyStart));
  r=await read(p);assert.equal(r.matches[m].authorityUid,'alice');assert.equal(r.matches[m].matchSize,4);
  for(const uid of ['alice','bob','carol','dave'])await assertSucceeds(change(uid,p,s=>ready(s,m,uid)));
  for(const uid of ['alice','bob','carol'])await assertSucceeds(db(uid).ref(`${p}/connections/${uid}/0`).set(true));
  await assertFails(change('alice',p,s=>playing(s,m)));                      // dave is not connected
  await assertSucceeds(db('dave').ref(`${p}/connections/dave/3`).set(true));
  await assertSucceeds(change('carol',p,s=>playing(s,m)));
  await assertFails(change('dave',p,s=>finish(s,m,[0,11,3,2])));
  await assertFails(change('alice',p,s=>finish(s,m,[0,12,3,2])));          // a 3/4 table ends exactly at the target
  await assertFails(change('alice',p,s=>finish(s,m,[0,11,11,2])));
  await assertSucceeds(change('alice',p,s=>finish(s,m,[0,11,3,3])));        // ties below the winner are allowed
});
test('SDK transactions: concurrent joins, Ready flags and starts of a 3-seat table commit exactly once each',async()=>{
  const kind='friendlyRooms',p=`${NS}/${kind}/ABCDEF`,m='ABCDEF_0_0_1';
  await reserve('alice',kind,'ABCDEF');
  await assertSucceeds(db('alice').ref(p).transaction(current=>current?undefined:room(kind,{tableSize:3})));
  assert.equal((await db('alice').ref(p).transaction(current=>current?undefined:room(kind,{tableSize:3}))).committed,false);
  for(const uid of ['bob','carol'])await reserve(uid,kind,'ABCDEF');
  await Promise.all(['bob','carol'].map(uid=>assertSucceeds(db(uid).ref(p).transaction(current=>current?add(current,uid):current))));
  const joined=await read(p);assert.equal(joined.rosterSize,3);assert.deepEqual(new Set(Object.values(joined.seats)),new Set([0,1,2]));
  await assertSucceeds(db('alice').ref(p).transaction(current=>current?friendlyStart(current):current));
  for(const uid of ['alice','bob','carol'])await assertSucceeds(db(uid).ref(`${p}/connections/${uid}/0`).set(true));
  await Promise.all(['alice','bob','carol'].map(uid=>assertSucceeds(db(uid).ref(p).transaction(current=>current?ready(current,m,uid):current))));
  assert.deepEqual(Object.keys((await read(p)).matches[m].ready).sort(),['alice','bob','carol']);
  await Promise.all(['alice','bob','carol'].map(uid=>assertSucceeds(db(uid).ref(p).transaction(current=>current&&current.matches[m].phase!=='PLAYING'?playing(current,m):current))));
  const started=(await read(p)).matches[m];assert.equal(started.starts,1);assert.equal(started.phase,'PLAYING');
});
test('friendly pair keeps the classic deuce rule and placement',async()=>{
  const kind='friendlyRooms',m='ABCDEF_0_0_1';
  const r=add(room(kind,{difficulty:2,target:11}),'bob');
  const p=await seed(kind,playing(friendlyStart(r),m));
  for(const scores of [[11,10],[12,9],[11,11],[10,8]])await assertFails(change('alice',p,s=>finish(s,m,scores)));
  await assertFails(change('alice',p,s=>{finish(s,m,[12,10]);s.matches[m].placement.reverse();return s}));
  await assertSucceeds(change('alice',p,s=>finish(s,m,[12,10])));
});
test('presence slots belong to their owner, including deletions inside a room rewrite',async()=>{
  const r=add(add(room('friendlyRooms',{tableSize:3}),'bob'),'carol'),p=await seed('friendlyRooms',r);
  await assertFails(db('eve').ref(`${p}/connections/eve/0`).set(true));
  await assertFails(db('bob').ref(`${p}/connections/alice/0`).set(true));
  await assertSucceeds(db('alice').ref(`${p}/connections/alice/0`).set(true));
  await assertSucceeds(db('alice').ref(`${p}/connections/alice/5`).set(true));
  await assertFails(db('bob').ref(`${p}/connections/alice/0`).remove());
  await assertFails(change('bob',p,s=>{delete s.connections.alice[0];return s}));
  await assertFails(change('bob',p,s=>{delete s.connections;return s}));
  await assertFails(db('alice').ref(`${p}/connections/alice/16`).set(true));
  await assertSucceeds(db('alice').ref(`${p}/connections/alice/0`).remove());
  await assertSucceeds(change('bob',p,s=>s));                                 // carrying presence through unchanged is fine
});
test('identity refresh only for oneself; house-player skills and characters validated',async()=>{
  const r=add(add(room('friendlyRooms',{tableSize:4}),'bob'),'bot_one'),p=await seed('friendlyRooms',r);
  await assertSucceeds(change('bob',p,s=>{s.participants.bob.identity.name='Bobby';return s}));
  await assertFails(change('bob',p,s=>{s.participants.alice.identity.name='Stolen';return s}));
  await assertFails(change('bob',p,s=>{s.participants.bob.bot=botProfile('mia');return s}));
  await assertFails(change('alice',p,s=>{s.participants.bot_one.bot.speed=11;return s}));
  await assertFails(change('alice',p,s=>{add(s,'bot_two');s.participants.bot_two.bot.characterId=s.participants.bot_one.bot.characterId;return s}));
  await assertSucceeds(change('alice',p,s=>add(s,'bot_two')));
});
test('house characters may repeat in a tournament ("Kyra 2"), never at a friendly table',async()=>{
  const kyra=(s,id,name)=>{add(s,id);s.participants[id].bot=botProfile('kyra');s.participants[id].identity.name=name;return s};
  const t=room('tournaments',{ids:['alice'],capacity:6,tableSize:3,format:'KNOCKOUT'}),p=await seed('tournaments',t);
  await assertSucceeds(change('alice',p,s=>kyra(s,'bot_a','Kyra')));
  await assertSucceeds(change('alice',p,s=>kyra(s,'bot_b','Kyra 2')));
  await assertSucceeds(change('alice',p,s=>{kyra(s,'bot_c','Kyra 3');return kyra(s,'bot_d','Kyra 4')}));
  const f=room('friendlyRooms',{tableSize:4,code:'BCDEFG'}),q=await seed('friendlyRooms',f);
  await assertSucceeds(change('alice',q,s=>kyra(s,'bot_a','Kyra')));
  await assertFails(change('alice',q,s=>kyra(s,'bot_b','Kyra 2')));
  await assertSucceeds(change('alice',q,s=>add(s,'bot_b')));                // another character is fine
});

// ---- game mode, advance and fixture goals ----
test('game mode and advance: written at creation only where allowed, then fixed',async()=>{
  const f=`${NS}/friendlyRooms/ABCDEF`;await reserve('alice','friendlyRooms','ABCDEF');
  await assertFails(db('alice').ref(f).set(room('friendlyRooms',{gameMode:'ELIMINATION'})));             // a pair plays the classic game
  await assertFails(db('alice').ref(f).set(room('friendlyRooms',{tableSize:3,gameMode:'WINNER_TAKES_ALL'})));   // only ELIMINATION is written
  await assertFails(db('alice').ref(f).set(room('friendlyRooms',{tableSize:3,advance:1})));             // advance belongs to group knockouts
  await assertSucceeds(db('alice').ref(f).set(room('friendlyRooms',{tableSize:3,gameMode:'ELIMINATION'})));
  for(const alter of [s=>{delete s.gameMode},s=>{s.gameMode='WINNER_TAKES_ALL'},s=>{s.advance=1}])await assertFails(change('alice',f,s=>{alter(s);return s}));
  await assertFails(db('alice').ref(`${f}/gameMode`).remove());
  const t=`${NS}/tournaments/BCDEFG`;await reserve('alice','tournaments','BCDEFG');
  const ko=o=>room('tournaments',{code:'BCDEFG',capacity:6,tableSize:3,format:'KNOCKOUT',...o});
  for(const bad of [{tableSize:2,gameMode:'ELIMINATION'},{tableSize:2,advance:1},{advance:2},{advance:0},{advance:'1'},{format:undefined,advance:1},{gameMode:'TOP_TWO'}])
    await assertFails(db('alice').ref(t).set(ko(bad)));
  await assertSucceeds(db('alice').ref(t).set(ko({gameMode:'ELIMINATION',advance:1})));
  for(const alter of [s=>{delete s.advance},s=>{delete s.gameMode},s=>{s.advance=2}])await assertFails(change('alice',t,s=>{alter(s);return s}));
  await assertSucceeds(change('alice',t,s=>add(s,'bot_a')));
  // a round-robin tournament of 3/4 may play ELIMINATION too
  await reserve('alice','tournaments','CDEFGH',1);
  await assertSucceeds(db('alice').ref(`${NS}/tournaments/CDEFGH`).set(room('tournaments',{code:'CDEFGH',capacity:4,tableSize:4,gameMode:'ELIMINATION'})));
});
test('fixture goals: TOP_TWO exactly at ELIMINATION tables sending two through before the final; immutable',async()=>{
  const ids=['alice','bob','carol','dave','erin','frank'];
  const r=room('tournaments',{ids,tableSize:3,format:'KNOCKOUT',code:'KNCDEF',gameMode:'ELIMINATION'}),p=await seed('tournaments',r);
  const good=start(clone(r));
  assert.equal(good.matches.KNCDEF_K0_0.goal,'TOP_TWO');assert.equal(good.matches.KNCDEF_K0_1.goal,'TOP_TWO');
  for(const alter of [s=>{delete s.matches.KNCDEF_K0_0.goal},s=>{s.matches.KNCDEF_K0_0.goal='TIEBREAK'},s=>{s.matches.KNCDEF_K0_0.goal='WIN'}])
    {const bad=clone(good);alter(bad);await assertFails(db('alice').ref(p).set(bad))}
  await assertSucceeds(db('alice').ref(p).set(good));
  await assertFails(change('alice',p,s=>{delete s.matches.KNCDEF_K0_1.goal;return s}));      // fixed once the fixture exists
  // winner takes all, advance 1 and the final never carry TOP_TWO
  for(const [o,code] of [[{},'BCDEFG'],[{gameMode:'ELIMINATION',advance:1},'CDEFGH']]){
    const x=room('tournaments',{ids,tableSize:3,format:'KNOCKOUT',code,...o}),q=await seed('tournaments',x);
    const plain=start(clone(x));assert.equal(plain.matches[`${code}_K0_0`].goal,undefined);
    const bad=clone(plain);bad.matches[`${code}_K0_0`].goal='TOP_TWO';await assertFails(db('alice').ref(q).set(bad));
    await assertSucceeds(db('alice').ref(q).set(plain));
  }
  const four=room('tournaments',{ids:ids.slice(0,4),tableSize:4,format:'KNOCKOUT',code:'DEFGHJ',gameMode:'ELIMINATION'}),q=await seed('tournaments',four);
  const final=start(clone(four));assert.equal(final.matches.DEFGHJ_K0_0.goal,undefined);
  const topFinal=clone(final);topFinal.matches.DEFGHJ_K0_0.goal='TOP_TWO';await assertFails(db('alice').ref(q).set(topFinal));
  await assertSucceeds(db('alice').ref(q).set(final));
  // round-robin and friendly fixtures carry no goal
  const rr=room('tournaments',{ids:['alice','bob','carol'],tableSize:3,code:'EFGHJK',gameMode:'ELIMINATION'}),rp=await seed('tournaments',rr);
  const scheduled=start(clone(rr));scheduled.matches.EFGHJK_T0_0.goal='TOP_TWO';await assertFails(db('alice').ref(rp).set(scheduled));
});

// ---- live transport ----
test('live: protocol 2 checkpoints by the authority only; seat-tagged action rings per human',async()=>{
  const kind='friendlyRooms',m='ABCDEF_0_0_1',live=`${NS}/live/${m}`;
  let r=room(kind,{tableSize:4});for(const id of ['bob','carol','bot_one'])add(r,id);
  r=online(playing(friendlyStart(r),m),'alice','bob','carol');await seed(kind,r);
  const players=r.matches[m].players,seat=uid=>players.indexOf(uid);
  const checkpoint={protocol:2,kind,code:'ABCDEF',engine:{protocol:2,referee:{scores:[0,0,0,0]}},seen:{bob:0},revision:1,authority:'alice',serverAt:Date.now(),clientAt:Date.now()};
  await assertFails(db('bob').ref(`${live}/checkpoint`).set({...checkpoint,authority:'bob'}));
  await assertFails(db('alice').ref(`${live}/checkpoint`).set({...checkpoint,protocol:1}));     // MatchLink is pairs only
  await assertFails(db('alice').ref(`${live}/checkpoint`).set({...checkpoint,revision:2}));
  await assertSucceeds(db('alice').ref(`${live}/checkpoint`).set(checkpoint));
  await assertFails(db('alice').ref(`${live}/checkpoint`).set(checkpoint));                     // revision must grow by one
  await assertFails(db('alice').ref(`${live}/checkpoint`).set({...checkpoint,revision:3}));
  await assertFails(db('alice').ref(`${live}/checkpoint`).set({...checkpoint,revision:2,code:'BCDEFG'}));
  await assertSucceeds(db('alice').ref(`${live}/checkpoint`).set({...checkpoint,revision:2}));
  await assertSucceeds(db('carol').ref(`${live}/checkpoint`).once('value'));
  const action={protocol:2,kind,code:'ABCDEF',sender:'carol',sequence:1,serverAt:Date.now(),rallyId:1,hitIndex:2,seat:seat('carol'),strike:{seat:seat('carol'),serve:false,rally:1,hit:2}};
  await assertSucceeds(db('carol').ref(`${live}/actions/carol/1`).set(action));
  await assertFails(db('carol').ref(`${live}/actions/carol/1`).set(action));                    // sequence must grow
  await assertFails(db('carol').ref(`${live}/actions/carol/2`).set({...action,sequence:2,seat:seat('bob')}));  // own seat only
  await assertFails(db('carol').ref(`${live}/actions/carol/3`).set({...action,sequence:2}));    // slot = sequence % 16
  await assertFails(db('bob').ref(`${live}/actions/carol/2`).set({...action,sender:'bob',sequence:2}));
  await assertFails(db('eve').ref(`${live}/actions/eve/1`).set({...action,sender:'eve',seat:0}));
  await assertFails(db('carol').ref(`${live}/actions/carol/2`).set({...action,sequence:2,protocol:1}));
  const {rallyId,...noRally}=action;await assertFails(db('carol').ref(`${live}/actions/carol/2`).set({...noRally,sequence:2}));
  await assertSucceeds(db('carol').ref(`${live}/actions/carol/1`).set({...action,sequence:17}));
  await assertFails(db('carol').ref(`${live}/remove`).set(true));
  await assertFails(db('carol').ref(live).remove());                           // the room still exists
  await assertSucceeds(db('alice').ref(`${NS}/${kind}/ABCDEF`).set(finish(clone(r),m,[7,3,1,0])));
  await assertFails(db('carol').ref(`${live}/actions/carol/2`).set({...action,sequence:18}));   // finished: no more live writes
  await assertFails(db('alice').ref(`${live}/checkpoint`).set({...checkpoint,revision:3}));
  await assertSucceeds(db('carol').ref(`${NS}/${kind}/ABCDEF`).remove());
  await assertSucceeds(db('carol').ref(live).remove());                        // the room is gone
});
test('live: classic pairs keep MatchLink protocol 1',async()=>{
  const kind='friendlyRooms',m='ABCDEF_0_0_1',live=`${NS}/live/${m}`;
  await seed(kind,online(playing(friendlyStart(add(room(kind),'bob')),m),'alice','bob'));
  const checkpoint={protocol:1,kind,code:'ABCDEF',engine:{score:0},seen:{},revision:1,authority:'alice',serverAt:Date.now()};
  await assertFails(db('bob').ref(`${live}/checkpoint`).set({...checkpoint,authority:'bob'}));
  await assertSucceeds(db('alice').ref(`${live}/checkpoint`).set(checkpoint));
  const action={protocol:1,kind,code:'ABCDEF',sender:'bob',sequence:1,serverAt:Date.now(),clientAt:Date.now(),flight:{x:.5},rallies:0,hit:0};
  await assertSucceeds(db('bob').ref(`${live}/actions/bob/1`).set(action));
  await assertFails(db('bob').ref(`${live}/actions/bob/2`).set({...action,sequence:2,flight:null}));
  await assertFails(db('alice').ref(`${live}/actions/bob/2`).set({...action,sequence:2}));
});

// ---- ELIMINATION tables and their duels ----
test('friendly ELIMINATION table: it ends with two survivors (no target), their classic duel decides the room',async()=>{
  const kind='friendlyRooms',m='ABCDEF_0_0_1',d='ABCDEF_0_0_1_D';
  let r=room(kind,{tableSize:3,gameMode:'ELIMINATION'});add(r,'bob');add(r,'bot_one');
  r=online(playing(friendlyStart(r),m),'alice','bob');const p=await seed(kind,r);
  assert.deepEqual(r.matches[m].players,['alice','bob','bot_one']);
  const res=finish(clone(r),m,[0,3,1],['bob','bot_one','alice']);           // bob and the house player survive
  assert.deepEqual(res.matches[d].players,['bob','bot_one']);assert.equal(res.matches[d].phase,'WAITING');assert.equal(res.state,'ACTIVE');
  for(const alter of [s=>{delete s.matches[d]},s=>{s.matches[d].players.reverse()},s=>{s.matches[d].players[1]='alice';s.matches[d].authorityUid='alice'},
    s=>{s.matches[d].goal='TIEBREAK'},s=>{s.state='FINISHED'},s=>{s.matches[m].scores=[0,8,1]},s=>{s.matches[m].placement=['bob','bot_one','bob']},
    s=>{s.matches[m].winner='bot_one'},s=>{s.matches.ABCDEF_0_0_2=clone(s.matches[d]);s.matches.ABCDEF_0_0_2.id='ABCDEF_0_0_2'}])
    {const bad=clone(res);alter(bad);await assertFails(db('alice').ref(p).set(bad))}
  await assertFails(db('bob').ref(p).set(res));                             // alice is the table's authority
  await assertSucceeds(db('alice').ref(p).set(res));
  await assertFails(change('alice',p,s=>{s.matches[d].players=['bob','alice'];return s}));     // the duel is fixed
  await assertSucceeds(change('bob',p,s=>ready(s,d,'bob')));
  await assertFails(change('alice',p,s=>ready(s,d,'alice')));               // not in the duel
  await assertSucceeds(change('bob',p,s=>playing(s,d)));
  for(const scores of [[1,0],[7,7],[8,5]])await assertFails(change('bob',p,s=>finish(s,d,scores)));   // the classic rule at the room target
  await assertSucceeds(change('bob',p,s=>finish(s,d,[5,7])));
  const done=await read(p);assert.equal(done.state,'FINISHED');assert.equal(done.matches[d].winner,'bot_one');
});
test('ELIMINATION house tables are written with their duel; a house duel is simulated at once',async()=>{
  // Round robin of 4 at tables of 3: four tables, one of them house-only.
  const rr=room('tournaments',{ids:['alice','bot_x','bot_y','bot_z'],tableSize:3,gameMode:'ELIMINATION'}),p=await seed('tournaments',rr);
  const good=start(clone(rr));
  const house=Object.values(good.matches).find(m=>m.matchSize===3&&list(m.players).every(x=>x.startsWith('bot_')));
  assert.equal(good.matches[`${house.id}_D`].phase,'FINISHED');
  await assertFails(db('alice').ref(p).set(others(good,`${house.id}_D`)));
  await assertSucceeds(db('alice').ref(p).set(good));
  // A human table's duel: created with the table's result, then played; the room finishes after every duel.
  let s=online(await read(p),'alice');const t=Object.values(s.matches).find(m=>m.matchSize===3&&list(m.players).includes('alice')).id;
  s=play(s,t);await seed('tournaments',s);
  const res=finish(clone(s),t,[2,1,0],list(s.matches[t].players));
  await assertFails(db('alice').ref(p).set(others(res,`${t}_D`)));
  await assertSucceeds(db('alice').ref(p).set(res));
  // Knockout with advance 1: every table is decided by its duel; the next round waits for the duels.
  const ids=['alice','bob','carol','dave','erin','frank'];
  let k=online(start(room('tournaments',{ids,tableSize:3,format:'KNOCKOUT',code:'KNCDEF',gameMode:'ELIMINATION',advance:1})),...ids);
  k=play(play(k,'KNCDEF_K0_0'),'KNCDEF_K0_1');const q=await seed('tournaments',k);
  k=finish(k,'KNCDEF_K0_0',[3,2,0],['frank','erin','dave']);
  assert.deepEqual(k.matches.KNCDEF_K0_0_D.players,['frank','erin']);
  await assertSucceeds(db('dave').ref(q).set(k));
  k=finish(k,'KNCDEF_K0_1',[0,2,1],['bob','alice','carol']);
  const early=clone(k);draw(early,['frank','bob'],1);
  await assertFails(db('alice').ref(q).set(early));                          // the duels are not decided yet
  await assertSucceeds(db('alice').ref(q).set(k));
  k=play(play(k,'KNCDEF_K0_0_D'),'KNCDEF_K0_1_D');await seed('tournaments',k);
  k=finish(k,'KNCDEF_K0_0_D',[7,4]);await assertSucceeds(db('erin').ref(q).set(k));
  k=finish(k,'KNCDEF_K0_1_D',[3,7]);                                         // alice beats bob
  assert.deepEqual(new Set(list(k.rounds[1].players)),new Set(['frank','alice']));assert.equal(k.matches.KNCDEF_K1_0.matchSize,2);
  await assertSucceeds(db('alice').ref(q).set(k));
});

// ---- group round robin (tables of 3/4) ----
test('group round robin: every size 3-8, tables of 3 and 4, one or two legs accept complete schedules',async()=>{
  for(let n=3;n<=8;n++)for(const tableSize of [3,4])for(const legs of [1,2]){
    const r=room('tournaments',{ids:['alice',...Array.from({length:n-1},(_,i)=>`bot_${i}`)],tableSize,legs});
    const p=await seed('tournaments',r);
    await assertSucceeds(change('alice',p,start));
    assert.equal(Object.keys((await read(p)).matches).length,TABLES[n][tableSize]*legs,`${n} players, tables of ${tableSize}`);
  }
});
test('group round robin: the host starts; wrong table counts, sizes, players or rotations are rejected',async()=>{
  const ids=['alice','bob','bot_x','bot_y','bot_z'];
  const r=room('tournaments',{ids,tableSize:3,legs:2}),p=await seed('tournaments',r);
  const good=start(clone(r));
  assert.equal(good.matches.ABCDEF_T0_2.phase,'FINISHED');                   // the house-only table is simulated at once
  const bad=[
    s=>{delete s.matches.ABCDEF_T0_4},
    s=>{s.matches.ABCDEF_T0_5=clone(s.matches.ABCDEF_T0_4);s.matches.ABCDEF_T0_5.id='ABCDEF_T0_5'},
    s=>{const m=s.matches.ABCDEF_T0_0;m.players.push('bot_z');m.scores.push(0);m.matchSize=4},
    s=>{s.matches.ABCDEF_T0_0.players[2]='bob'},
    s=>{s.matches.ABCDEF_T0_0.players[2]='outsider'},
    s=>{const m=s.matches.ABCDEF_T1_0;m.players=[...s.matches.ABCDEF_T0_0.players]},
    s=>{s.matches.ABCDEF_T0_0.authorityUid='bob'},
    s=>{s.matches.ABCDEF_T0_2.scores=[7,7,0]},
    s=>{s.matches.ABCDEF_T0_0.phase='FINISHED'},
    s=>{s.state='FINISHED'},
    s=>{s.matches.ABCDEF_T0_2_D=fixture(s,'ABCDEF_T0_2_D',list(s.matches.ABCDEF_T0_2.placement).slice(0,2))},   // no duel without ELIMINATION
  ];
  for(const alter of bad){const next=clone(good);alter(next);await assertFails(db('alice').ref(p).set(next))}
  await assertFails(db('bob').ref(p).set(good));
  await assertSucceeds(db('alice').ref(p).set(good));
  await assertFails(change('alice',p,s=>{delete s.matches.ABCDEF_T1_3;return s}));
  await assertFails(db('alice').ref(`${p}/matches/ABCDEF_T0_1`).remove());
  await assertFails(change('alice',p,s=>{delete s.participants.bot_z;s.roster=s.roster.filter(x=>x!=='bot_z');s.rosterSize=4;return s}));   // the roster is fixed after the start
});
test('group round robin: Ready/start once per table, no human at two live tables, authority results',async()=>{
  const r=online(start(room('tournaments',{ids:['alice','bob','carol','bot_x'],tableSize:3})),'alice','bob','carol');
  const p=await seed('tournaments',r),[t0,t1]=['ABCDEF_T0_0','ABCDEF_T0_1'];
  assert.deepEqual(r.matches[t0].players,['alice','bob','bot_x']);assert.deepEqual(r.matches[t1].players,['bob','bot_x','carol']);
  await assertSucceeds(change('alice',p,s=>ready(s,t0,'alice')));
  await assertSucceeds(change('bob',p,s=>ready(s,t0,'bob')));
  await assertSucceeds(change('alice',p,s=>playing(s,t0)));
  await assertFails(change('alice',p,s=>{s.matches[t0].starts=0;s.matches[t0].phase='WAITING';return s}));
  for(const uid of ['bob','carol'])await assertSucceeds(change(uid,p,s=>ready(s,t1,uid)));
  await assertFails(change('carol',p,s=>playing(s,t1)));                     // bob is already playing table 0
  await assertFails(change('bob',p,s=>finish(s,t0,[2,7,0])));                // authority is alice
  await assertFails(change('alice',p,s=>finish(s,t0,[2,7,7])));
  await assertSucceeds(change('alice',p,s=>finish(s,t0,[2,7,0])));
  await assertSucceeds(change('carol',p,s=>playing(s,t1)));
  await assertFails(change('alice',p,s=>{s.matches[t0].scores=[7,2,0];return s}));
});
test('group round robin: a departure cancels only the leaver\'s unfinished tables and passes management on',async()=>{
  let r=online(start(room('tournaments',{ids:['alice','bob','carol','bot_x'],tableSize:3})),'alice','bob','carol');
  r=finish(playing(ready(ready(r,'ABCDEF_T0_0','alice'),'ABCDEF_T0_0','bob'),'ABCDEF_T0_0'),'ABCDEF_T0_0',[7,3,0]);
  const p=await seed('tournaments',r),left=leave(clone(r),'alice');
  assert.equal(left.host,'bob');
  for(const tamper of [s=>{s.matches.ABCDEF_T0_1.phase='CANCELLED'},s=>{s.matches.ABCDEF_T0_0.phase='CANCELLED'},s=>{s.host='bot_x'},s=>{delete s.departed}]){
    const bad=clone(left);tamper(bad);await assertFails(db('alice').ref(p).set(bad));
  }
  await assertFails(db('bob').ref(p).set(left));                             // nobody evicts a peer
  await assertSucceeds(db('alice').ref(p).set(left));
  const saved=await read(p);
  assert.equal(saved.matches.ABCDEF_T0_0.phase,'FINISHED');assert.equal(saved.matches.ABCDEF_T0_2.phase,'CANCELLED');assert.equal(saved.matches.ABCDEF_T0_1.phase,'WAITING');
  await assertFails(db('alice').ref(`${p}/connections/alice/0`).set(true));
  await assertFails(change('alice',p,s=>{delete s.departed.alice;return s}));
});

// ---- group knockout (tables of 3/4, 2..32 players): structural draws ----
test('group knockout: the host starts every size 3-9 with tables of 3/4, walkovers instead of byes and settled house tables',async()=>{
  const names=['alice','bob','carol','dave','erin','frank','grace','hank','ivy'];
  for(let n=3;n<=9;n++)for(const tableSize of [3,4]){
    const ids=n<=4?names.slice(0,n):['alice','bob',...Array.from({length:n-2},(_,i)=>`bot_${i}`)];
    const r=room('tournaments',{ids,tableSize,format:'KNOCKOUT',code:'KNCDEF'}),p=await seed('tournaments',r);
    const next=start(clone(r));
    assert.ok(Object.values(next.rounds).every(d=>!d.byes));
    await assertFails(db('bob').ref(p).set(next));
    await assertSucceeds(db('alice').ref(p).set(next),`${n} players, tables of ${tableSize}`);
  }
});
test('group knockout: 15 players at tables of 4 draw 4+4+4+3; every table has exactly its fixture',async()=>{
  const ids=Array.from({length:15},(_,i)=>`p${String(i).padStart(2,'0')}`);
  const r=room('tournaments',{ids,tableSize:4,format:'KNOCKOUT',code:'KNCDEF'}),p=await seed('tournaments',r);
  const good=start(clone(r));
  assert.deepEqual(list(good.rounds[0].tables).map(t=>t.length),[4,4,4,3]);assert.equal(Object.keys(good.matches).length,4);
  assert.deepEqual(good.matches.KNCDEF_K0_3.players,list(good.rounds[0].tables)[3]);
  for(const alter of [
    s=>{delete s.matches.KNCDEF_K0_3},                                                  // every table has its fixture
    s=>{s.matches.KNCDEF_K0_4=fixture(s,'KNCDEF_K0_4',['p00','p01','p02'])},            // no fixture without a table
    s=>{s.matches.KNCDEF_K0_1.players.reverse()},                                       // seat order is the table's
    s=>{const m=s.matches.KNCDEF_K0_3;m.players.push('p00');m.scores.push(0);m.matchSize=4},
    s=>{s.rounds[0].count=14;s.rounds[0].players.pop()},                                 // seats are the round's players
    s=>{s.rounds[0].players[14]=s.rounds[0].players[0]},                                // distinct players
    s=>{s.rounds[0].players[14]='outsider';s.rounds[0].tables[3][2]='outsider';s.matches.KNCDEF_K0_3.players[2]='outsider'},
    s=>{s.rounds[0].tables[2][1]=s.rounds[0].tables[2][0]},                             // distinct seats
    s=>{s.rounds[0].byes=[s.rounds[0].players[14]]},                                    // no byes in a new draw
    s=>{s.rounds[0].tables[4]=['p00','p01']},                                           // a table needs its fixture
    s=>{s.rounds[0].count=16},
    s=>{s.rounds[1]={count:4,players:['p00','p01','p02','p03'],tables:[['p00','p01','p02','p03']]};s.matches.KNCDEF_K1_0=fixture(s,'KNCDEF_K1_0',['p00','p01','p02','p03'])},  // round 0 is still playing
    s=>{s.rounds[2]=s.rounds[0]},                                                       // rounds are contiguous
  ]){const bad=clone(good);alter(bad);await assertFails(db('p00').ref(p).set(bad))}
  await assertFails(db('p01').ref(p).set(good));                                         // the host starts
  await assertSucceeds(db('p00').ref(p).set(good));
  for(const alter of [s=>{s.rounds[0].tables[0].reverse();s.matches.KNCDEF_K0_0.players.reverse()},s=>{s.rounds[0].players.reverse()},s=>{delete s.rounds[0]},
    s=>{delete s.rounds[0].tables[3];delete s.matches.KNCDEF_K0_3},s=>{s.rounds[0].walkovers=[['p00']]}])
    await assertFails(change('p00',p,s=>{alter(s);return s}));                           // draws are frozen
  await assertFails(db('p00').ref(`${p}/matches/KNCDEF_K0_1/players/0`).set('p14'));
});
test('group knockout: a 32-player draw is accepted at tables of 4 and of 3; 33 players are rejected',async()=>{
  for(const tableSize of [4,3]){
    const ids=['alice',...Array.from({length:31},(_,i)=>`bot_${String(i).padStart(2,'0')}`)];
    const r=room('tournaments',{ids,tableSize,format:'KNOCKOUT',code:'KNCDEF'}),p=await seed('tournaments',r);
    const next=start(clone(r));
    assert.equal(next.rounds[0].count,32);assert.equal(list(next.rounds[0].tables).length,tableSize===4?8:10);
    await assertSucceeds(db('alice').ref(p).set(next),`32 players at tables of ${tableSize}`);
    const extra=clone(r);extra.state='ACTIVE';draw(extra,[...ids,'alice'].reverse(),0);   // 33 seats
    await assertFails(db('alice').ref(p).set(extra));
  }
  const big=['alice',...Array.from({length:32},(_,i)=>`bot_${String(i).padStart(2,'0')}`)];
  await assertFails(db('alice').ref(`${NS}/tournaments/LMNPQR`).set(room('tournaments',{ids:big,tableSize:4,format:'KNOCKOUT',code:'LMNPQR'})));
  await reserve('alice','tournaments','LMNPQR');
  await assertFails(db('alice').ref(`${NS}/tournaments/LMNPQR`).set(room('tournaments',{capacity:33,tableSize:4,format:'KNOCKOUT',code:'LMNPQR'})));
  await assertFails(db('alice').ref(`${NS}/tournaments/LMNPQR`).set(room('tournaments',{capacity:10,tableSize:2,format:'KNOCKOUT',code:'LMNPQR'})));   // classic pairs stay 2-9
  await assertFails(db('alice').ref(`${NS}/tournaments/LMNPQR`).set(room('tournaments',{capacity:9,tableSize:3,code:'LMNPQR'})));                       // round robin stays 3-8
  await assertSucceeds(db('alice').ref(`${NS}/tournaments/LMNPQR`).set(room('tournaments',{capacity:32,tableSize:4,format:'KNOCKOUT',code:'LMNPQR'})));
});
test('group knockout: five players draw a table of 3 and a walkover of 2 that goes through with the top two',async()=>{
  const ids=['alice','bob','carol','dave','erin'];
  const r=online(room('tournaments',{ids,tableSize:3,format:'KNOCKOUT',code:'KNCDEF'}),...ids),p=await seed('tournaments',r);
  const good=start(clone(r));
  assert.deepEqual(list(good.rounds[0].tables),[['erin','dave','carol']]);assert.deepEqual(list(good.rounds[0].walkovers),[['bob','alice']]);
  for(const alter of [s=>{s.rounds[0].walkovers=[['bob','alice','carol']]},s=>{s.rounds[0].walkovers=[['bob','outsider']]},
    s=>{s.rounds[0].walkovers=[['bob','bob']]},s=>{s.rounds[0].walkovers=[['bob']];s.rounds[0].byes=['alice']}])
    {const bad=clone(good);alter(bad);await assertFails(db('alice').ref(p).set(bad))}
  await assertSucceeds(db('alice').ref(p).set(good));
  let s=play(await read(p),'KNCDEF_K0_0');await seed('tournaments',s);
  const next=finish(clone(s),'KNCDEF_K0_0',[7,5,2]);                        // erin, dave + the walkover bob, alice
  assert.deepEqual(new Set(list(next.rounds[1].players)),new Set(['erin','dave','bob','alice']));assert.equal(list(next.rounds[1].tables).length,1);
  await assertSucceeds(db('carol').ref(p).set(next));
  // advance 1: a table of 2 is played instead; a walkover there, or in a final, is rejected
  const one=room('tournaments',{ids,tableSize:3,format:'KNOCKOUT',code:'BCDEFG',advance:1}),q=await seed('tournaments',one);
  const played=start(clone(one));
  assert.deepEqual(list(played.rounds[0].tables).map(t=>t.length),[3,2]);assert.equal(played.rounds[0].walkovers,undefined);
  const skipped=clone(played);skipped.rounds[0].walkovers=[skipped.rounds[0].tables.pop()];delete skipped.matches.BCDEFG_K0_1;
  await assertFails(db('alice').ref(q).set(skipped));
  await assertSucceeds(db('alice').ref(q).set(played));
  const four=room('tournaments',{ids:ids.slice(0,4),tableSize:3,format:'KNOCKOUT',code:'CDEFGH'}),f=await seed('tournaments',four);
  const final=start(clone(four));final.rounds[0].walkovers=[['alice']];
  await assertFails(db('alice').ref(f).set(final));
});
test('group knockout: a round stored before walkovers keeps its bye and stays playable',async()=>{
  const ids=['alice','bob','carol','dave','erin'];
  let r=online(room('tournaments',{ids,tableSize:4,format:'KNOCKOUT',code:'KNCDEF'}),...ids);
  r.state='ACTIVE';r.rounds=[{count:5,players:['erin','dave','carol','bob','alice'],tables:[['erin','dave','carol','bob']],byes:['alice']}];
  r.matches={KNCDEF_K0_0:fixture(r,'KNCDEF_K0_0',['erin','dave','carol','bob'])};
  const p=await seed('tournaments',r);
  await assertSucceeds(change('bob',p,s=>ready(s,'KNCDEF_K0_0','bob')));
  await assertFails(change('bob',p,s=>{s.rounds[0].byes=['erin'];return s}));
  await assertFails(change('bob',p,s=>{delete s.rounds[0].byes;return s}));
  let s=play(await read(p),'KNCDEF_K0_0');await seed('tournaments',s);
  const next=finish(clone(s),'KNCDEF_K0_0',[7,5,2,1]);                      // erin, dave + the bye alice
  assert.deepEqual(new Set(list(next.rounds[1].players)),new Set(['erin','dave','alice']));assert.equal(next.rounds[1].byes,undefined);
  await assertSucceeds(db('bob').ref(p).set(next));
});
test('group knockout: a round is drawn only after the previous one is decided; the final table ends it; results stay',async()=>{
  const ids=['alice','bob','carol','dave','erin','frank'];
  let r=online(start(room('tournaments',{ids,tableSize:3,format:'KNOCKOUT',code:'KNCDEF'})),...ids);
  const p=await seed('tournaments',r);
  assert.deepEqual(r.rounds[0].tables,[['frank','erin','dave'],['carol','bob','alice']]);
  r=play(play(r,'KNCDEF_K0_0'),'KNCDEF_K0_1');await seed('tournaments',r);
  r=finish(r,'KNCDEF_K0_0',[7,2,4]);                                         // frank, dave go through; erin is out
  await assertFails(db('frank').ref(p).set(r));                              // dave is the authority
  await assertSucceeds(db('dave').ref(p).set(r));
  await assertFails(change('dave',p,s=>draw(s,['frank','dave'],1)));        // table 1 is still playing
  const good=finish(clone(r),'KNCDEF_K0_1',[5,7,1]);                         // bob, carol go through; alice is out
  assert.deepEqual(new Set(list(good.rounds[1].players)),new Set(['frank','dave','bob','carol']));assert.equal(good.rounds[1].tables.length,1);
  const nextDraw=(s,players)=>{delete s.rounds[1];delete s.matches.KNCDEF_K1_0;return draw(s,players,1)};
  for(const players of [['frank','dave','bob','bob'],['frank','dave','bob','outsider']])     // participants, once each
    await assertFails(db('alice').ref(p).set(nextDraw(clone(good),players)));
  const noDraw=clone(good);delete noDraw.rounds[1];delete noDraw.matches.KNCDEF_K1_0;noDraw.state='ACTIVE';
  await assertFails(db('alice').ref(p).set(noDraw));                         // an ACTIVE round has something to play
  const early=clone(good);early.state='FINISHED';await assertFails(db('alice').ref(p).set(early));
  await assertSucceeds(db('alice').ref(p).set(good));
  r=play(good,'KNCDEF_K1_0');await seed('tournaments',r);
  const authority=r.matches.KNCDEF_K1_0.authorityUid;
  const final=finish(clone(r),'KNCDEF_K1_0',[3,7,0,6]);
  assert.equal(final.state,'FINISHED');
  const extra=clone(final);draw(extra,list(final.matches.KNCDEF_K1_0.placement).slice(0,2),2);extra.state='ACTIVE';
  await assertFails(db(authority).ref(p).set(extra));                        // after a played final nobody plays on
  await assertSucceeds(db(authority).ref(p).set(final));
  await assertFails(change('alice',p,s=>{s.state='ACTIVE';return s}));
  await assertFails(change('alice',p,s=>{s.matches.KNCDEF_K0_0.scores=[2,7,4];return s}));
  await assertFails(change('alice',p,s=>{delete s.rounds[0];return s}));
  await assertFails(change('alice',p,s=>{delete s.matches.KNCDEF_K1_0;return s}));
});
test('group knockout: a tie for the runner-up place adds a one-point tie-break of exactly the tied players',async()=>{
  const ids=['alice','bob','carol','dave','erin','frank'];
  let r=online(start(room('tournaments',{ids,tableSize:3,format:'KNOCKOUT',code:'KNCDEF',difficulty:2,target:11})),...ids);
  r=play(play(r,'KNCDEF_K0_0'),'KNCDEF_K0_1');const p=await seed('tournaments',r);
  const tb='KNCDEF_K0_0_T',tied=finish(clone(r),'KNCDEF_K0_0',[11,4,4]);     // frank wins; erin and dave tie for second
  assert.deepEqual(tied.matches[tb].players,['erin','dave']);assert.equal(tied.matches[tb].goal,'TIEBREAK');
  for(const alter of [s=>{s.matches[tb].players=['erin','frank']},s=>{delete s.matches[tb].goal},s=>{s.matches[tb].goal='TOP_TWO'},
    s=>{const m=s.matches[tb];m.players.push('frank');m.scores.push(0);m.matchSize=3}])
    {const bad=clone(tied);alter(bad);await assertFails(db('dave').ref(p).set(bad))}
  const clear=finish(clone(r),'KNCDEF_K0_0',[11,5,4]);clear.matches[tb]=fixture(clear,tb,['erin','dave'],'TIEBREAK');clear.state='ACTIVE';
  await assertFails(db('dave').ref(p).set(clear));                           // no tie, no tie-break
  await assertSucceeds(db('dave').ref(p).set(tied));
  let s=finish(await read(p),'KNCDEF_K0_1',[11,7,2]);                        // table 1 is decided; the round waits for the tie-break
  assert.equal(s.rounds[1],undefined);await assertSucceeds(db('alice').ref(p).set(s));
  await assertFails(change('alice',p,x=>draw(x,['frank','dave','carol','bob'],1)));
  s=play(await read(p),tb);await seed('tournaments',s);
  for(const scores of [[2,0],[0,0],[1,1],[11,9]])await assertFails(change('dave',p,x=>finish(x,tb,scores)));   // one point decides, whatever the difficulty
  await assertSucceeds(change('dave',p,x=>finish(x,tb,[0,1])));             // dave wins the tie-break
  const next=await read(p);
  assert.deepEqual(new Set(list(next.rounds[1].players)),new Set(['frank','dave','carol','bob']));
  // three players tied at a table of 4: a three-seat tie-break, one point
  const eight=['alice','bob','carol','dave','erin','frank','grace','hank'];
  let x=online(start(room('tournaments',{ids:eight,tableSize:4,format:'KNOCKOUT',code:'BCDEFG'})),...eight);
  x=play(x,'BCDEFG_K0_0');const q=await seed('tournaments',x);
  x=finish(x,'BCDEFG_K0_0',[7,3,3,3]);assert.equal(x.matches.BCDEFG_K0_0_T.matchSize,3);
  const authority=x.matches.BCDEFG_K0_0.authorityUid;
  const missing=clone(x);const m=missing.matches.BCDEFG_K0_0_T;m.players.pop();m.scores.pop();m.matchSize=2;m.authorityUid=list(m.players).sort()[0];
  await assertFails(db(authority).ref(q).set(missing));                      // every tied player plays
  await assertSucceeds(db(authority).ref(q).set(x));
  x=play(x,'BCDEFG_K0_0_T');await seed('tournaments',x);
  const tbAuthority=x.matches.BCDEFG_K0_0_T.authorityUid;
  for(const scores of [[1,1,0],[2,0,0],[0,0,0]])await assertFails(change(tbAuthority,q,y=>finish(y,'BCDEFG_K0_0_T',scores)));
  await assertSucceeds(change(tbAuthority,q,y=>finish(y,'BCDEFG_K0_0_T',[0,0,1])));
});
test('group knockout ELIMINATION: TOP_TWO tables end with two survivors, the final table\'s duel crowns the winner',async()=>{
  const ids=['alice','bob','carol','dave','erin','frank'];
  let r=online(start(room('tournaments',{ids,tableSize:3,format:'KNOCKOUT',code:'KNCDEF',gameMode:'ELIMINATION'})),...ids);
  r=play(play(r,'KNCDEF_K0_0'),'KNCDEF_K0_1');const p=await seed('tournaments',r);
  const t0='KNCDEF_K0_0',a0=r.matches[t0].authorityUid;                     // frank, erin, dave: dave
  for(const [scores,placement] of [[[8,2,0],['frank','erin','dave']],[[3,2,1],['frank','frank','dave']],[[3,2,1],['frank','erin']]])
    await assertFails(change(a0,p,s=>finish(s,t0,scores,placement)));
  await assertFails(change(a0,p,s=>{finish(s,t0,[3,2,0],['frank','erin','dave']);s.matches[t0].winner='erin';return s}));
  await assertFails(change(a0,p,s=>{finish(s,t0,[3,2,0],['frank','erin','dave']);s.matches[`${t0}_D`]=fixture(s,`${t0}_D`,['frank','erin']);return s}));   // TOP_TWO: both go through, no duel
  await assertSucceeds(change(a0,p,s=>finish(s,t0,[3,2,0],['frank','erin','dave'])));   // no target requirement
  r=await read(p);const t1='KNCDEF_K0_1',a1=r.matches[t1].authorityUid;
  const next=finish(clone(r),t1,[1,0,2],['alice','carol','bob']);
  assert.equal(list(next.rounds[1].tables)[0].length,4);assert.equal(next.matches.KNCDEF_K1_0.goal,undefined);
  await assertSucceeds(db(a1).ref(p).set(next));
  let s=play(await read(p),'KNCDEF_K1_0');await seed('tournaments',s);
  const fa=s.matches.KNCDEF_K1_0.authorityUid,order=list(s.matches.KNCDEF_K1_0.players);
  const fin=finish(clone(s),'KNCDEF_K1_0',[2,1,0,0],order);
  assert.deepEqual(fin.matches.KNCDEF_K1_0_D.players,order.slice(0,2));assert.equal(fin.state,'ACTIVE');
  for(const alter of [s=>{delete s.matches.KNCDEF_K1_0_D},s=>{s.matches.KNCDEF_K1_0_D.players.reverse()},s=>{s.state='FINISHED'}])
    {const bad=clone(fin);alter(bad);await assertFails(db(fa).ref(p).set(bad))}
  await assertSucceeds(db(fa).ref(p).set(fin));
  s=play(await read(p),'KNCDEF_K1_0_D');await seed('tournaments',s);
  const da=s.matches.KNCDEF_K1_0_D.authorityUid;
  await assertFails(change(da,p,x=>finish(x,'KNCDEF_K1_0_D',[1,0])));      // the duel plays to the room target
  await assertSucceeds(change(da,p,x=>finish(x,'KNCDEF_K1_0_D',[7,4])));
  const done=await read(p);assert.equal(done.state,'FINISHED');
  await assertFails(change(da,p,x=>{x.matches.KNCDEF_K1_0_D.scores=[4,7];return x}));
});
test('group knockout: a departure cancels the table as a walkover; every remaining player advances',async()=>{
  const ids=['alice','bob','carol','dave','erin','frank'];
  const r=online(start(room('tournaments',{ids,tableSize:3,format:'KNOCKOUT',code:'KNCDEF'})),...ids);
  const p=await seed('tournaments',r);
  const left=leave(clone(r),'erin');                                         // table 0: frank, erin, dave
  assert.equal(left.matches.KNCDEF_K0_0.phase,'CANCELLED');assert.equal(left.matches.KNCDEF_K0_0.winner,'frank');
  for(const tamper of [s=>{s.matches.KNCDEF_K0_0.winner='dave'},s=>{s.matches.KNCDEF_K0_1.phase='CANCELLED';s.matches.KNCDEF_K0_1.winner='carol'},s=>{delete s.departed}]){
    const bad=clone(left);tamper(bad);await assertFails(db('erin').ref(p).set(bad));
  }
  await assertFails(db('frank').ref(p).set(left));
  await assertSucceeds(db('erin').ref(p).set(left));
  let s=await read(p);s=play(s,'KNCDEF_K0_1');await seed('tournaments',s);
  const next=finish(clone(s),'KNCDEF_K0_1',[7,5,0]);                          // carol, bob + walkover frank, dave
  assert.deepEqual(new Set(list(next.rounds[1].players)),new Set(['frank','dave','carol','bob']));
  await assertFails(db(s.matches.KNCDEF_K0_1.authorityUid).ref(p).set(nextWith(next,'erin')));   // never a departed player
  await assertSucceeds(db(s.matches.KNCDEF_K0_1.authorityUid).ref(p).set(next));
});
// The same draw with one player replaced.
function nextWith(s,id){const x=clone(s);const players=list(x.rounds[1].players);players[3]=id;delete x.rounds[1];delete x.matches.KNCDEF_K1_0;return draw(x,players,1)}
test('group knockout: a departure from the final table leaves a classic pair final, drawn in the same write',async()=>{
  const ids=['alice','bob','carol'];
  const r=online(start(room('tournaments',{ids,tableSize:3,format:'KNOCKOUT',code:'KNCDEF'})),...ids);
  const p=await seed('tournaments',r);
  const left=leave(clone(r),'bob');
  assert.equal(left.matches.KNCDEF_K0_0.phase,'CANCELLED');assert.deepEqual(left.rounds[1].tables,[['alice','carol']]);
  const twice=clone(left);delete twice.rounds[1];delete twice.matches.KNCDEF_K1_0;draw(twice,['alice','carol','alice'],1);
  await assertFails(db('bob').ref(p).set(twice));
  const over=clone(left);delete over.rounds[1];delete over.matches.KNCDEF_K1_0;over.state='FINISHED';
  await assertFails(db('bob').ref(p).set(over));                            // two players remain: they play on
  await assertSucceeds(db('bob').ref(p).set(left));
  let s=await read(p);s=play(s,'KNCDEF_K1_0');await seed('tournaments',s);
  await assertFails(change('alice',p,x=>finish(x,'KNCDEF_K1_0',[8,3])));      // the classic pair rule: the target exactly
  await assertFails(change('carol',p,x=>finish(x,'KNCDEF_K1_0',[7,3])));     // alice is the authority
  await assertSucceeds(change('alice',p,x=>finish(x,'KNCDEF_K1_0',[3,7])));
  const done=await read(p);assert.equal(done.state,'FINISHED');assert.equal(done.matches.KNCDEF_K1_0.winner,'carol');
});
test('a stranger is denied everywhere in a group knockout: room, draw, fixtures, presence, departures and live data',async()=>{
  const ids=['alice','bob','carol','dave'];
  const r=online(play(start(room('tournaments',{ids,tableSize:4,format:'KNOCKOUT',code:'KNCDEF'})),'KNCDEF_K0_0'),...ids);
  const p=await seed('tournaments',r),m='KNCDEF_K0_0',live=`${NS}/live/${m}`;
  const finished=finish(clone(r),m,[7,3,2,0]);
  await assertFails(db('eve').ref(p).set(finished));
  await assertFails(change('eve',p,s=>{s.lastActivityAt=Date.now();return s}));
  await assertFails(db('eve').ref(`${p}/rounds/1`).set({count:2,players:['alice','bob'],tables:[['alice','bob']]}));
  await assertFails(db('eve').ref(`${p}/matches/${m}/phase`).set('CANCELLED'));
  await assertFails(db('eve').ref(`${p}/matches/${m}_T`).set(fixture(r,`${m}_T`,['bob','carol'],'TIEBREAK')));
  await assertFails(db('eve').ref(`${p}/connections/eve/0`).set(true));
  await assertFails(db('eve').ref(`${p}/departed/eve`).set(true));
  await assertFails(db('eve').ref(`${p}/participants/eve`).set({identity:identity('eve')}));
  await assertFails(db('eve').ref(`${live}/checkpoint`).set({protocol:2,kind:'tournaments',code:'KNCDEF',engine:{},revision:1,authority:'eve',serverAt:Date.now()}));
  await assertFails(db('eve').ref(`${live}/actions/eve/1`).set({protocol:2,kind:'tournaments',code:'KNCDEF',sender:'eve',sequence:1,serverAt:Date.now(),rallyId:1,hitIndex:0,seat:0,strike:{}}));
  await assertFails(db('eve').ref(p).remove());
  await assertFails(db().ref(p).once('value'));
  await assertSucceeds(db(r.matches[m].authorityUid).ref(p).set(finished));   // the members themselves still can
});

// ---- classic pair tournaments stay available in the new namespace ----
test('classic pair round robin and knockout (tableSize 2) still work',async()=>{
  const rr=room('tournaments',{ids:['alice','bob','bot_x'],legs:2}),p=await seed('tournaments',rr);
  await assertSucceeds(change('alice',p,start));
  assert.equal(Object.keys((await read(p)).matches).length,6);
  await assertFails(change('alice',p,s=>{s.matches.ABCDEF_0_0_1.players.reverse();return s}));
  const ko=room('tournaments',{ids:['alice','bob','carol','dave','erin'],format:'KNOCKOUT',code:'KNCDEF'});
  let r=online(start(clone(ko)),'alice','bob','carol','dave','erin');const q=await seed('tournaments',r);
  while(r.state!=='FINISHED'){
    const m=Object.values(r.matches).find(m=>m.phase==='WAITING');m.phase='PLAYING';m.starts=1;await seed('tournaments',r);
    const next=finish(clone(r),m.id,[7,3]);
    await assertFails(db(m.players.find(x=>x!==m.authorityUid)).ref(q).set(next));
    await assertSucceeds(db(m.authorityUid).ref(q).set(next));
    r=next;
  }
  await assertFails(change('alice',q,s=>{s.state='ACTIVE';return s}));
});

// ---- room lifecycle ----
test('tournament: outsiders and members cannot change settings; waiting host leaves to a connected human',async()=>{
  const r=online(room('tournaments',{ids:['alice','bob','bot_x'],tableSize:3,capacity:4}),'alice','bob'),p=await seed('tournaments',r);
  for(const [k,v] of [['host','bob'],['tableSize',4],['target',5],['capacity',3],['createdAt',1]])await assertFails(change('bob',p,s=>{s[k]=v;return s}));
  await assertFails(change('eve',p,s=>{s.target=5;return s}));
  await assertFails(change('bob',p,s=>{delete s.participants.bot_x;s.roster=['alice','bob'];s.rosterSize=2;return s}));
  await assertFails(change('bob',p,s=>add(s,'bot_y')));
  await assertSucceeds(change('alice',p,s=>add(s,'bot_y')));
  await assertSucceeds(change('alice',p,s=>{delete s.participants.bot_y;s.roster=Object.keys(s.participants).sort();s.rosterSize=3;return s}));
  await assertFails(change('alice',p,s=>{s.seats={alice:0};return s}));
  await assertFails(db('alice').ref(p).remove());                           // bob is connected
  await assertSucceeds(db('alice').ref(p).set(leave(await read(p),'alice')));
  assert.equal((await read(p)).host,'bob');
  await assertSucceeds(db('bob').ref(p).remove());                          // now the only connected human
});
test('stale rooms: bounded cleanup query and atomic room/live removal; fresh or connected rooms protected',async()=>{
  const age=15*86400000,m='ABCDEF_T0_0';
  const r=playing(start(room('tournaments',{ids:['alice','bob','carol'],tableSize:3})),m);r.createdAt-=age;r.lastActivityAt-=age;
  const p=await seed('tournaments',r),live=`${NS}/live/${m}`;
  await admin(d=>d.ref(live).set({checkpoint:{kind:'tournaments',code:'ABCDEF'},actions:{bob:{1:{sequence:1}}}}));
  const ref=db('eve').ref(`${NS}/tournaments`),cutoff=Math.floor(Date.now()/60000)*60000-14*86400000;
  await assertFails(ref.once('value'));
  await assertFails(ref.orderByChild('lastActivityAt').endAt(Date.now()).limitToFirst(50).once('value'));
  await assertFails(ref.orderByChild('lastActivityAt').endAt(cutoff).limitToFirst(51).once('value'));
  await assertSucceeds(ref.orderByChild('lastActivityAt').endAt(cutoff).limitToFirst(50).once('value'));
  await assertSucceeds(db('eve').ref().update({[p]:null,[live]:null}));
  assert.equal(await read(p),null);assert.equal(await read(live),null);
  r.lastActivityAt=Date.now();await seed('tournaments',r);await assertFails(db('eve').ref(p).remove());
  r.lastActivityAt=Date.now()-age;r.connections={alice:{0:true}};await seed('tournaments',r);await assertFails(db('eve').ref(p).remove());
});
test('activity stamps come from members, never go backwards and cannot be erased',async()=>{
  const r=add(room('friendlyRooms',{tableSize:3}),'bob');r.lastActivityAt-=8*86400000;const p=await seed('friendlyRooms',r);
  await assertSucceeds(db('bob').ref(`${p}/lastActivityAt`).set(Date.now()));
  await assertFails(db('alice').ref(`${p}/lastActivityAt`).set(r.lastActivityAt));
  await assertFails(db('alice').ref(`${p}/lastActivityAt`).remove());
  await assertFails(db('eve').ref(`${p}/lastActivityAt`).set(Date.now()));
});

// ---- isolation from the original app ----
test('Cross Pong flows cannot write into minikPingPong, and Ping Pong shapes are rejected here',async()=>{
  const kind='friendlyRooms';
  await assertSucceeds(db('alice').ref(`minikPingPong/openSlots/alice/${kind}/0`).set('ABCDEF'));
  await assertFails(db('alice').ref(`minikPingPong/${kind}/ABCDEF`).set(room(kind,{tableSize:3})));     // tableSize/seats are unknown there
  const cross=online(playing(friendlyStart(add(add(room(kind,{tableSize:3}),'bob'),'carol')),'ABCDEF_0_0_1'),'alice','bob','carol');
  await admin(d=>d.ref(`minikPingPong/${kind}/ABCDEF`).set(cross));
  await assertFails(change('alice',`minikPingPong/${kind}/ABCDEF`,s=>finish(s,'ABCDEF_0_0_1',[7,3,0])));
  await assertFails(db('alice').ref('minikPingPong/live/ABCDEF_0_0_1/checkpoint').set({protocol:2,kind,code:'ABCDEF',engine:{},revision:1,authority:'alice',serverAt:Date.now()}));
  // A Ping Pong room (a/b fixtures, no tableSize) is not a Cross Pong room.
  await reserve('alice',kind,'BCDEFG');
  const old={...room(kind,{code:'BCDEFG'})};delete old.tableSize;delete old.seats;
  await assertFails(db('alice').ref(`${NS}/${kind}/BCDEFG`).set(old));
  const pair=online(friendlyStart(add(room(kind,{code:'BCDEFG'}),'bob')),'alice','bob');const m=pair.matches.BCDEFG_0_0_1;
  Object.assign(m,{a:'alice',b:'bob',scoreA:0,scoreB:0});await seed(kind,pair);
  await assertFails(change('alice',`${NS}/${kind}/BCDEFG`,s=>s));
});
