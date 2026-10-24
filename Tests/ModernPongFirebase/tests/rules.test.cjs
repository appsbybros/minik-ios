const {before, after, beforeEach, test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
let env;
const mergedPath = path.resolve(__dirname, '../rules/merged.json');
const projectId = 'demo-minik-pingpong';
before(async () => {
  assert.match(process.env.FIREBASE_DATABASE_EMULATOR_HOST||'',/^127\.0\.0\.1:[0-9]+$/,'Explicit local emulator required; never use production');
  env = await initializeTestEnvironment({projectId, database:{host:'127.0.0.1',port:Number(process.env.FIREBASE_DATABASE_EMULATOR_HOST.split(':')[1]),rules:fs.readFileSync(mergedPath,'utf8')}});
});
after(async () => {if(env) await env.cleanup()});
beforeEach(async () => {await env.clearDatabase()});
const db = uid => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).database();
test('full rules deny unauthenticated root access', async () => {
  await assertFails(db().ref().once('value'));
  await assertFails(db().ref('minikPingPong/profiles/host').set({id:'host', name:'Host', avatar:0}));
});

const clone = o => structuredClone(o);
const identity = id => ({id,name:id,avatar:0});
const bot = {speed:9,reaction:9,accuracy:9,power:9,agility:9,characterId:'kyra',forehandSkill:9,backhandSkill:9,serveSkill:9};
function room(kind='friendlyRooms', ids=['alice','bob'], code='ABCDEF', capacity=ids.length) {
  return {code,kind:kind==='friendlyRooms'?'FRIENDLY':'TOURNAMENT',host:ids[0],capacity,legs:1,winPoints:3,lossPoints:0,difficulty:0,target:7,
    participants:Object.fromEntries(ids.map(id=>[id,{identity:identity(id),...(id.startsWith('bot_')?{bot}: {})}])),
    roster:ids.slice().sort(),rosterSize:ids.length,state:'WAITING',createdAt:Date.now(),lastActivityAt:Date.now()};
}
function schedule(r) {
  r=clone(r); r.state='ACTIVE';r.matches={};const ids=Object.keys(r.participants).sort();
  for(let leg=0;leg<r.legs;leg++)for(let i=0;i<ids.length;i++)for(let j=i+1;j<ids.length;j++) {
    const id=`${r.code}_${leg}_${i}_${j}`, a=ids[leg?j:i],b=ids[leg?i:j];
    const humans=[a,b].filter(id=>!r.participants[id].bot).sort();
    r.matches[id]={id,a,b,seed:123,phase:humans.length?'WAITING':'FINISHED',authorityUid:humans[0]||r.host,starts:0,scoreA:humans.length?0:7,scoreB:0,winner:humans.length?'':a};
  } return r;
}
async function seed(kind,r) {await env.withSecurityRulesDisabled(c=>c.database().ref(`minikPingPong/${kind}/${r.code}`).set(r));return `minikPingPong/${kind}/${r.code}`}
async function reserve(uid,kind,code,slot=0){return assertSucceeds(db(uid).ref(`minikPingPong/openSlots/${uid}/${kind}/${slot}`).set(code));}
async function read(p) {return (await db('alice').ref(p).once('value')).val()}
async function change(uid,p,fn) {
  const current=await read(p); const next=fn(clone(current))||current;
  return db(uid).ref(p).set(next);
}
function joined(r,id) {r.participants[id]={identity:identity(id)};r.roster=Object.keys(r.participants).sort();r.rosterSize=r.roster.length;return r}
function ready(r,uid) {const m=Object.values(r.matches)[0];m.phase='READY';m.ready={...m.ready,[uid]:true};return r}
function playing(r) {const m=Object.values(r.matches)[0];m.phase='PLAYING';m.starts=1;delete m.ready;return r}
function finish(r) {const m=Object.values(r.matches)[0];m.phase='FINISHED';m.scoreA=7;m.scoreB=3;m.winner=m.a;r.state='FINISHED';return r}

test('only Ping Pong room namespaces differ from the captured live rules', () => {
  const supplied=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../rules/original.json'),'utf8'));
  const merged=JSON.parse(fs.readFileSync(mergedPath,'utf8'));
  const fragment=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../rules/pingpong.json'),'utf8'));
  assert.deepEqual(merged.rules.minikPingPong,fragment.rules.minikPingPong);
  for(const root of ["minikPingPong","minikPongTeams"]){delete supplied.rules[root];delete merged.rules[root]}assert.deepEqual(merged,supplied);
});
test('collection scans and unknown namespaces denied even to authenticated users',async()=>{
  for(const p of [undefined,'minikPingPong','minikPingPong/profiles','minikPingPong/friendlyRooms','minikPingPong/tournaments','minikPingPong/live','minikPingPong/leaderboard'])await assertFails(db('alice').ref(p).once('value'));
  await assertFails(db('alice').ref('minikPingPong/leaderboard/alice').set({score:99}));
});
test('own profile accepted; impersonation and invalid name/avatar rejected',async()=>{
  await assertSucceeds(db('alice').ref('minikPingPong/nicknames/GreenFrog').set('alice'));
  await assertSucceeds(db('alice').ref('minikPingPong/profiles/alice').set({...identity('alice'),name:'GreenFrog',updatedAt:12345}));
  await assertFails(db('bob').ref('minikPingPong/profiles/alice').set(identity('alice')));
  for(const bad of [{name:''},{name:'x'.repeat(19)},{id:'bob'},{avatar:6},{avatar:1.5}])await assertFails(db('alice').ref('minikPingPong/profiles/alice').set({...identity('alice'),...bad}));
});
for(const kind of ['friendlyRooms','tournaments']) {
  test(`${kind}: create/read/join works; full, unauthenticated and fake host rejected`,async()=>{
    const r=room(kind,['alice'],'ABCDEF',2),p=`minikPingPong/${kind}/ABCDEF`;
    await assertFails(db('bob').ref(p).set(r));await assertFails(db().ref(p).set(r));
    await reserve('alice',kind,r.code);await reserve('bob',kind,r.code);
    await assertSucceeds(db('alice').ref(p).set(r));
    await assertSucceeds(db('bob').ref(p).once('value')); // Knowing a code is the MVP read capability.
    await assertSucceeds(change('bob',p,r=>joined(r,'bob')));
    await assertFails(change('eve',p,r=>joined(r,'eve')));
    await assertFails(db().ref(p).once('value'));
  });
  test(`${kind}: outsiders cannot overwrite/delete rooms, members cannot alter settings/host`,async()=>{
    const p=await seed(kind,room(kind));
    await assertFails(change('eve',p,r=>{r.target=11;return r}));
    await assertFails(db('eve').ref(p).remove());
    for(const [k,v] of [['host','bob'],['target',11],['difficulty',3],['createdAt',999]])await assertFails(change('bob',p,r=>{r[k]=v;return r}));
  });
  test(`${kind}: own identity edit allowed before start; other identity and roster deletion blocked`,async()=>{
    const p=await seed(kind,room(kind));
    await assertSucceeds(change('bob',p,r=>{r.participants.bob.identity.name='Bobby';return r}));
    await assertFails(change('bob',p,r=>{r.participants.alice.identity.name='Stolen';return r}));
    await assertFails(change('bob',p,r=>{delete r.participants.alice;r.roster=['bob'];r.rosterSize=1;return r}));
    await assertFails(db('bob').ref(`${p}/participants/alice`).remove());
  });
  test(`${kind}: host creates schedule, ready persists, both present start once, authority saves immutable result`,async()=>{
    let r=room(kind);const p=await seed(kind,r),m=`${r.code}_0_0_1`;
    await assertFails(db('bob').ref(p).set(schedule(r)));
    await assertSucceeds(db('alice').ref(p).set(schedule(r)));
    await assertSucceeds(change('alice',p,r=>ready(r,'alice')));
    await assertFails(change('alice',p,r=>ready(r,'bob')));
    await assertSucceeds(change('bob',p,r=>ready(r,'bob')));
    await assertFails(change('alice',p,playing));
    for(const uid of ['alice','bob'])await assertSucceeds(db(uid).ref(`${p}/connections/${uid}/0`).set(true));
    await assertSucceeds(db('alice').ref(`${p}/connections/alice/0`).remove());
    assert.equal((await read(p)).matches[m].ready.alice,true);
    await assertSucceeds(db('alice').ref(`${p}/connections/alice/0`).set(true));
    await assertSucceeds(change('bob',p,playing));
    await assertFails(change('alice',p,r=>{r.matches[m].starts++;return r}));
    await assertFails(change('bob',p,finish));
    await assertSucceeds(change('alice',p,finish));
    await assertSucceeds(db('alice').ref(p).set(await read(p)));
    await assertFails(change('alice',p,r=>{r.matches[m].scoreB=4;return r}));
    await assertFails(db('alice').ref(`${p}/matches/${m}`).remove());
  });
  test(`${kind}: presence belongs to members themselves, including deletion via room transaction`,async()=>{
    const p=await seed(kind,room(kind));
    await assertFails(db('eve').ref(`${p}/connections/eve/0`).set(true));
    await assertFails(db('bob').ref(`${p}/connections/alice/0`).set(true));
    await assertSucceeds(db('alice').ref(`${p}/connections/alice/0`).set(true));
    await assertFails(db('bob').ref(`${p}/connections/alice/0`).remove());
    await assertFails(change('bob',p,r=>{delete r.connections;return r}));
    await assertSucceeds(db('alice').ref(`${p}/connections/alice/0`).remove());
  });
  test(`${kind}: bot skills validated, host add/remove supported, non-host cannot become bot`,async()=>{
    const r=room(kind,['alice'],'ABCDEF',2),p=await seed(kind,r);
    const withBot=clone(r);withBot.participants.bot_kyra={identity:identity('bot_kyra'),bot};withBot.roster=['alice','bot_kyra'];withBot.rosterSize=2;
    await assertSucceeds(db('alice').ref(p).set(withBot));
    await assertFails(change('alice',p,r=>{r.participants.bot_kyra.bot.forehandSkill=11;return r}));
    await reserve('alice',kind,r.code);await reserve('bob',kind,r.code);
    await assertSucceeds(db('alice').ref(p).set(r));
    await assertSucceeds(change('bob',p,r=>joined(r,'bob')));
    await assertFails(change('bob',p,r=>{r.participants.bob.bot=bot;return r}));
  });
}
test('either friendly participant may Finish a saved or playing game; outsiders and tournament deletion remain protected',async()=>{
  const r=schedule(room());
  for(const state of [room(),r,playing(clone(r)),finish(playing(clone(r)))]){
    const p=await seed('friendlyRooms',state);
    await assertFails(db('eve').ref(p).remove());
    await assertSucceeds(db('alice').ref(p).remove());
    await seed('friendlyRooms',state);
    await assertSucceeds(db('bob').ref(p).remove());
  }
  const alone=room('friendlyRooms',['alice'],'ABCDEF',2);const p=await seed('friendlyRooms',alone);
  await assertFails(db('bob').ref(p).remove());await assertSucceeds(db('alice').ref(p).remove());
  const tr=room('tournaments');tr.connections={alice:{0:true},bob:{0:true}};
  const t=await seed('tournaments',tr);await assertFails(db('alice').ref(t).remove());
});
test('Finish deletes the live checkpoint only after the friendly room is removed',async()=>{
  const r=playing(schedule(room()));const p=await seed('friendlyRooms',r);const live='minikPingPong/live/ABCDEF_0_0_1';
  await env.withSecurityRulesDisabled(c=>c.database().ref(live).set({checkpoint:{kind:'friendlyRooms',code:'ABCDEF'}}));
  await assertFails(db('bob').ref(live).remove());
  await assertSucceeds(db('bob').ref(p).remove());
  await assertSucceeds(db('bob').ref(live).remove());
});
test('full mixed tournament schedule and deterministic bot results accepted atomically',async()=>{
  let r=room('tournaments',['alice','bob','bot_flare','bot_kyra']);r.legs=2;
  const p=await seed('tournaments',r);await assertSucceeds(db('alice').ref(p).set(schedule(r)));
  const current=await read(p);assert.equal(Object.keys(current.matches).length,12);
  await assertFails(change('alice',p,r=>{delete r.matches.ABCDEF_1_0_1;return r}));
  await assertFails(change('alice',p,r=>{r.matches.fake=Object.values(r.matches)[0];return r}));
});
test('checkpoint authority/revision and live action ownership/ring order',async()=>{
  const r=playing(schedule(room()));await seed('friendlyRooms',r);const m='ABCDEF_0_0_1',p=`minikPingPong/live/${m}`;
  const checkpoint={protocol:1,kind:'friendlyRooms',code:'ABCDEF',engine:{score:0},revision:1,authority:'alice',serverAt:Date.now()};
  await assertSucceeds(db('alice').ref(`${p}/checkpoint`).once('value'));
  await assertFails(db('bob').ref(`${p}/checkpoint`).set({...checkpoint,authority:'bob'}));
  await assertSucceeds(db('alice').ref(`${p}/checkpoint`).set(checkpoint));
  await assertFails(db('alice').ref(`${p}/checkpoint`).set(checkpoint));
  await assertSucceeds(db('alice').ref(`${p}/checkpoint`).set({...checkpoint,revision:2}));
  const action={protocol:1,kind:'friendlyRooms',code:'ABCDEF',sender:'bob',sequence:1,serverAt:Date.now(),clientAt:Date.now(),flight:{x:.5},rallies:0,hit:0};
  await assertSucceeds(db('bob').ref(`${p}/actions/bob/1`).set(action));
  await assertFails(db('bob').ref(`${p}/actions/bob/1`).set(action));
  await assertFails(db('alice').ref(`${p}/actions/bob/1`).set({...action,sequence:17}));
  await assertFails(db('eve').ref(`${p}/actions/eve/1`).set({...action,sender:'eve'}));
  await assertFails(db('bob').ref(`${p}/actions/bob/16`).set({...action,sequence:16}));
  await assertSucceeds(db('bob').ref(`${p}/actions/bob/1`).set({...action,sequence:17}));
  await assertSucceeds(db('alice').ref('minikPingPong/friendlyRooms/ABCDEF').set(finish(r)));
  await assertFails(db('bob').ref(`${p}/actions/bob/2`).set({...action,sequence:18}));
});
test('unchanged TripleShot own-user and leaderboard rules still work; cross-user writes denied',async()=>{
  const profile={uid:'alice',displayName:'Alice',createdAt:123,updatedAt:124};
  await assertSucceeds(db('alice').ref('tripleShot/users/alice/profile').set(profile));
  await assertFails(db('bob').ref('tripleShot/users/alice/profile').set(profile));
  await assertFails(db('bob').ref('tripleShot/users/alice').once('value'));
  await assertSucceeds(db('alice').ref('tripleShot/leaderboard/alice').set({uid:'alice',name:'Alice',bestScore:5}));
  await assertSucceeds(db('bob').ref('tripleShot/leaderboard').once('value'));
  await assertFails(db().ref('tripleShot/leaderboard').once('value'));
});

test('all tournament sizes 2–8 and both legs accept complete schedules',async()=>{
  for(let size=2;size<=8;size++)for(let legs=1;legs<=2;legs++) {
    const ids=['alice',...Array.from({length:size-1},(_,i)=>`bot_${i}`)];
    const r=room('tournaments',ids);r.legs=legs;r.difficulty=3;
    const p=await seed('tournaments',r);
    await assertSucceeds(db('alice').ref(p).set(schedule(r)));
    assert.equal(Object.keys((await read(p)).matches).length,size*(size-1)/2*legs);
  }
});
test('roster index cannot hide a participant or exceed capacity',async()=>{
  const r=room('tournaments'),p=await seed('tournaments',r);
  await assertFails(db('alice').ref(p).update({roster:['alice'],rosterSize:1}));
  await assertFails(change('alice',p,r=>{r.participants.eve={identity:identity('eve')};return r}));
  await assertFails(change('bob',p,r=>{r.roster=['bob','alice'];return r}));
});
test('host cannot skip Ready; non-authority cannot change scores while playing',async()=>{
  const r=schedule(room()),p=await seed('friendlyRooms',r);
  for(const uid of ['alice','bob'])await assertSucceeds(db(uid).ref(`${p}/connections/${uid}/0`).set(true));
  await assertFails(change('alice',p,playing));
  await seed('friendlyRooms',playing(r));
  await assertFails(change('bob',p,r=>{r.matches.ABCDEF_0_0_1.scoreB=7;return r}));
  await assertFails(change('alice',p,r=>{r.matches.ABCDEF_0_0_1.phase='READY';return r}));
});
test('invalid final scores rejected; hard deuce result accepted',async()=>{
  const r=playing(schedule(room()));r.difficulty=2;const p=await seed('friendlyRooms',r);
  for(const scores of [[0,0],[6,3],[7,6],[9,6]]) {
    const next=finish(r);next.matches.ABCDEF_0_0_1.scoreA=scores[0];next.matches.ABCDEF_0_0_1.scoreB=scores[1];
    await assertFails(db('alice').ref(p).set(next));
  }
  const next=finish(r);next.matches.ABCDEF_0_0_1.scoreA=9;next.matches.ABCDEF_0_0_1.scoreB=7;
  await assertSucceeds(db('alice').ref(p).set(next));
});
test('SDK transactions reserve a code once and persist concurrent independent Ready flags',async()=>{
  const r=room('friendlyRooms',['alice'],'ABCDEF',2),p=`minikPingPong/friendlyRooms/${r.code}`;
  await reserve('alice','friendlyRooms',r.code);await reserve('bob','friendlyRooms',r.code);
  await assertSucceeds(db('alice').ref(p).transaction(current=>current?undefined:r));
  const duplicate=await db('alice').ref(p).transaction(current=>current?undefined:r);assert.equal(duplicate.committed,false);
  await assertSucceeds(db('bob').ref(p).transaction(current=>current?joined(current,'bob'):current));
  await assertSucceeds(db('alice').ref(p).set(schedule(joined(r,'bob'))));
  await Promise.all(['alice','bob'].map(uid=>assertSucceeds(db(uid).ref(p).transaction(current=>current?ready(current,uid):current))));
  const saved=await read(p);assert.equal(saved.matches.ABCDEF_0_0_1.ready.alice,true);assert.equal(saved.matches.ABCDEF_0_0_1.ready.bob,true);
});
test('onDisconnect removes only own presence token, preserving room and Ready',async()=>{
  const r=ready(schedule(room()),'bob'),p=await seed('friendlyRooms',r);
  const client=db('bob'),token=client.ref(`${p}/connections/bob/3`);
  await assertSucceeds(token.onDisconnect().remove());await assertSucceeds(token.set(true));
  client.goOffline();
  let saved;
  for(let attempt=0;attempt<30;attempt++) {
    saved=await read(p);if(!saved.connections?.bob?.[3])break;
    await new Promise(resolve=>setTimeout(resolve,100));
  }
  assert.equal(saved.matches.ABCDEF_0_0_1.ready.bob,true);
  assert.ok(!saved.connections?.bob?.[3]);
});

test('unified friendly: add house player, schedule, Ready and start with existing production rules',async()=>{
  const kind='friendlyRooms',r=room(kind,['alice'],'ABCDEF',2),p=`minikPingPong/${kind}/ABCDEF`;
  await reserve('alice',kind,r.code);await reserve('bob',kind,r.code);
  await assertSucceeds(db('alice').ref(p).set(r));
  await assertSucceeds(db('alice').ref(`${p}/connections/alice/0`).set(true));
  await assertSucceeds(change('alice',p,n=>{n.participants.bot_kyra={identity:identity('bot_kyra'),bot};n.roster=['alice','bot_kyra'];n.rosterSize=2;return n}));
  await assertFails(change('bob',p,n=>joined(n,'bob')));
  await assertSucceeds(change('alice',p,schedule));
  await assertSucceeds(change('alice',p,n=>ready(n,'alice')));
  await assertSucceeds(change('alice',p,playing));
  const m=Object.values((await read(p)).matches)[0];assert.equal(m.starts,1);assert.equal(m.phase,'PLAYING');
});

test('unified friendly: house selection cannot overwrite a human who joined first',async()=>{
  const r=room('friendlyRooms',['alice'],'ABCDEF',2),p=await seed('friendlyRooms',r);
  const stale=clone(r);stale.participants.bot_kyra={identity:identity('bot_kyra'),bot};stale.roster=['alice','bot_kyra'];stale.rosterSize=2;
  await reserve('bob','friendlyRooms',r.code);
  await assertSucceeds(change('bob',p,n=>joined(n,'bob')));
  await assertFails(db('alice').ref(p).set(stale));
  assert.equal((await read(p)).participants.bob.identity.id,'bob');
});

test('generated nicknames are exclusive, bilingual, and reject free text',async()=>{
  const claim=uid=>db(uid).ref('minikPingPong/nicknames/GreenFrog').transaction(v=>v&&v!==uid?undefined:uid);
  const claims=await Promise.all(['alice','bob'].map(claim));
  assert.equal(claims.filter(r=>r.committed).length,1);
  const owner=(await db('alice').ref('minikPingPong/nicknames/GreenFrog').once('value')).val();
  const other=owner==='alice'?'bob':'alice';
  await assertFails(db(other).ref('minikPingPong/nicknames/GreenFrog').set(other));
  await assertSucceeds(db(other).ref('minikPingPong/nicknames/GreenFrog22').set(other));
  await assertSucceeds(db('alice').ref('minikPingPong/nicknames/צפרדע ירוקה').set('alice'));
  for(const n of ['FreeText','GreenFrog0','GreenFrog10000'])await assertFails(db('alice').ref(`minikPingPong/nicknames/${n}`).set('alice'));
  await assertFails(db('alice').ref('minikPingPong/profiles/alice').set({...identity('alice'),name:'FreeText'}));
});

test('three open slots per category cannot be bypassed or removed while active',async()=>{
  const codes=['ABCDEF','BCDEFG','CDEFGH'];
  for(const kind of ['friendlyRooms','tournaments'])for(const [slot,code] of codes.entries()){
    await reserve('alice',kind,code,slot);
    await assertSucceeds(db('alice').ref(`minikPingPong/${kind}/${code}`).set(room(kind,['alice'],code,2)));
  }
  const slots='minikPingPong/openSlots/alice/friendlyRooms';
  await assertFails(db('alice').ref(`${slots}/3`).set('DEFGHJ'));
  await assertFails(db('alice').ref(`${slots}/0`).set('DEFGHJ'));
  await assertFails(db('alice').ref(slots).remove());
  await assertFails(db('bob').ref(slots).once('value'));
  await assertFails(db('alice').ref('minikPingPong/friendlyRooms/DEFGHJ').set(room('friendlyRooms',['alice'],'DEFGHJ',2)));
  await assertSucceeds(db('alice').ref('minikPingPong/friendlyRooms/ABCDEF').remove());
  await assertSucceeds(db('alice').ref(`${slots}/0`).set('DEFGHJ'));
});

test('joining requires own free reservation; creation without one is rejected',async()=>{
  const r=room('tournaments',['alice'],'ABCDEF',2),p=await seed('tournaments',r);
  await assertFails(change('bob',p,r=>joined(r,'bob')));
  await reserve('bob','tournaments',r.code);
  await assertSucceeds(change('bob',p,r=>joined(r,'bob')));
});

test('activity uses any member, cannot go backwards or be erased',async()=>{
  const r=room('tournaments');r.createdAt-=10*86400000;r.lastActivityAt-=8*86400000;
  const p=await seed('tournaments',r);
  await assertSucceeds(db('bob').ref(`${p}/lastActivityAt`).set(Date.now()));
  await assertFails(db('alice').ref(`${p}/lastActivityAt`).set(r.lastActivityAt));
  await assertFails(db('alice').ref(`${p}/lastActivityAt`).remove());
  await assertFails(db('eve').ref(`${p}/lastActivityAt`).set(Date.now()));
});

test('bounded stale query and atomic room/live cleanup; fresh or connected sessions protected',async()=>{
  const age=15*86400000,r=playing(schedule(room('tournaments')));r.createdAt-=age;r.lastActivityAt-=age;
  const p=await seed('tournaments',r),live='minikPingPong/live/ABCDEF_0_0_1';
  await env.withSecurityRulesDisabled(c=>c.database().ref(live).set({checkpoint:{kind:'tournaments',code:r.code},actions:{bob:{1:{sequence:1}}}}));
  const ref=db('eve').ref('minikPingPong/tournaments');
  await assertFails(ref.once('value'));
  await assertFails(ref.orderByChild('lastActivityAt').endAt(Date.now()).limitToFirst(50).once('value'));
  const cutoff=Math.floor(Date.now()/60000)*60000-14*86400000;
  await assertSucceeds(ref.orderByChild('lastActivityAt').endAt(cutoff).limitToFirst(50).once('value'));
  await assertSucceeds(ref.orderByChild('lastActivityAt').startAfter(null,'AAAAAA').endAt(cutoff).limitToFirst(50).once('value'));
  await assertFails(ref.orderByChild('lastActivityAt').endAt(cutoff).limitToFirst(51).once('value'));
  await assertSucceeds(db('eve').ref().update({[p]:null,[live]:null}));
  assert.equal(await read(p),null);
  await env.withSecurityRulesDisabled(async c=>assert.equal((await c.database().ref(live).once('value')).val(),null));
  r.lastActivityAt=Date.now();await seed('tournaments',r);await assertFails(db('eve').ref(p).remove());
  r.lastActivityAt=Date.now()-age;r.connections={alice:{0:true}};await seed('tournaments',r);await assertFails(db('eve').ref(p).remove());
  delete r.connections;delete r.lastActivityAt;await seed('tournaments',r);await assertSucceeds(db('eve').ref(p).remove());
});

test('house player character cannot be selected twice, distinct characters allowed',async()=>{
  const r=room('tournaments',['alice','bot_kyra'],'ABCDEF',3),p=await seed('tournaments',r);
  function add(characterId){const n=clone(r);n.participants.bot_other={identity:identity('bot_other'),bot:{...bot,characterId}};n.roster=Object.keys(n.participants).sort();n.rosterSize=3;return n;}
  await assertFails(db('alice').ref(p).set(add('kyra')));
  await assertSucceeds(db('alice').ref(p).set(add('flare')));
});

function leaveTournament(r,uid){
  r=clone(r);const peer=Object.keys(r.participants).sort().find(p=>p!==uid&&!r.participants[p].bot&&!r.departed?.[p]&&Object.keys(r.connections?.[p]||{}).length);
  if(r.host===uid)r.host=peer;
  if(r.state==='WAITING'){delete r.participants[uid];r.roster=Object.keys(r.participants).sort();r.rosterSize=r.roster.length;}
  else {
    r.departed={...r.departed,[uid]:true};
    for(const m of Object.values(r.matches)){
      if((m.a===uid||m.b===uid)&&!['FINISHED','CANCELLED'].includes(m.phase)){m.phase='CANCELLED';delete m.ready;}
      if(r.participants[m.a].bot&&r.participants[m.b].bot)m.authorityUid=r.host;
    }
    r.state=Object.values(r.matches).every(m=>['FINISHED','CANCELLED'].includes(m.phase))?'FINISHED':'ACTIVE';
  }
  delete r.connections[uid];return r;
}
test('tournament deletion allowed to sole connected human even non-host and during play',async()=>{
  for(const phase of ['WAITING','PLAYING','FINISHED']){
    let r=room('tournaments',['alice','bob','bot_kyra']);
    if(phase!=='WAITING'){r=schedule(r);r.matches.ABCDEF_0_0_1.phase=phase;r.matches.ABCDEF_0_0_1.starts=1;}
    r.connections={bob:{0:true}};const p=await seed('tournaments',r);
    await assertFails(db('eve').ref(p).remove());
    await assertFails(db('alice').ref(p).remove()); // A different connected human exists.
    await assertSucceeds(db('bob').ref(p).remove());
  }
});
test('waiting host leaves, transfers to connected human and frees own slot',async()=>{
  const r=room('tournaments',['alice','bob','bot_kyra']);r.connections={alice:{0:true},bob:{0:true}};
  const p=await seed('tournaments',r);await reserve('alice','tournaments',r.code);
  await assertSucceeds(db('alice').ref(p).set(leaveTournament(r,'alice')));
  assert.equal((await read(p)).host,'bob');
  await assertSucceeds(db('alice').ref('minikPingPong/openSlots/alice/tournaments/0').remove());
  await assertFails(db('alice').ref(`${p}/connections/alice/0`).set(true));
});
test('active departure preserves scores, cancels only leaver fixtures and transfers management',async()=>{
  let r=schedule(room('tournaments',['alice','bob','bot_flare','bot_kyra']));
  r.connections={alice:{0:true},bob:{0:true}};
  const completed=r.matches.ABCDEF_0_0_1;Object.assign(completed,{phase:'FINISHED',scoreA:7,scoreB:3,winner:'alice',starts:1});
  const p=await seed('tournaments',r);await reserve('alice','tournaments',r.code);
  const left=leaveTournament(r,'alice');await assertSucceeds(db('alice').ref(p).set(left));
  const saved=await read(p);assert.deepEqual(saved.matches.ABCDEF_0_0_1,completed);assert.equal(saved.host,'bob');
  assert.equal(saved.matches.ABCDEF_0_0_2.phase,'CANCELLED');assert.equal(saved.matches.ABCDEF_0_1_2.phase,'WAITING');
  await assertSucceeds(db('alice').ref('minikPingPong/openSlots/alice/tournaments/0').remove());
  await assertFails(db('alice').ref(`${p}/connections/alice/0`).set(true));
  await assertFails(db('alice').ref(`${p}/lastActivityAt`).set(Date.now()));
  const tamper=clone(left);delete tamper.departed;await assertFails(db('bob').ref(p).set(tamper));
  await assertSucceeds(db('bob').ref(p).remove());
});
test('departure cannot evict a peer, steal host, alter results or cancel unrelated matches',async()=>{
  let r=schedule(room('tournaments',['alice','bob','carol']));r.connections={alice:{0:true},bob:{0:true},carol:{0:true}};
  const p=await seed('tournaments',r);
  await assertFails(db('bob').ref(p).set(leaveTournament(r,'alice')));
  const stolen=clone(r);stolen.host='bob';await assertFails(db('bob').ref(p).set(stolen));
  const bad=leaveTournament(r,'alice');bad.matches.ABCDEF_0_1_2.phase='CANCELLED';await assertFails(db('alice').ref(p).set(bad));
  const badScore=leaveTournament(r,'alice');badScore.matches.ABCDEF_0_0_1.scoreA=7;await assertFails(db('alice').ref(p).set(badScore));
  const noPeer=clone(r);noPeer.connections={alice:{0:true}};await seed('tournaments',noPeer);
  const disconnected=leaveTournament(r,'alice');await assertFails(db('alice').ref(p).set(disconnected));
});
test('concurrent Ready flags start exactly once; same human cannot start another fixture',async()=>{
  const r=schedule(room('tournaments',['alice','bob','carol']));r.connections={alice:{0:true},bob:{0:true},carol:{0:true}};
  const p=await seed('tournaments',r),m='ABCDEF_0_0_1';
  await Promise.all(['alice','bob'].map(uid=>assertSucceeds(db(uid).ref(p).transaction(s=>s?ready(s,uid):s))));
  await Promise.all(['alice','bob'].map(uid=>assertSucceeds(db(uid).ref(p).transaction(s=>s&&s.matches[m].phase!=='PLAYING'?playing(s):s))));
  assert.equal((await read(p)).matches[m].starts,1);
  const next=await read(p);next.matches.ABCDEF_0_0_2.ready={alice:true,carol:true};next.matches.ABCDEF_0_0_2.phase='READY';
  await env.withSecurityRulesDisabled(c=>c.database().ref(p).set(next));
  next.matches.ABCDEF_0_0_2.phase='PLAYING';next.matches.ABCDEF_0_0_2.starts=1;delete next.matches.ABCDEF_0_0_2.ready;
  await assertFails(db('alice').ref(p).set(next));
});
test('deleted tournament live state can be cleaned; existing live state cannot',async()=>{
  const r=playing(schedule(room('tournaments')));r.connections={alice:{0:true}};
  const p=await seed('tournaments',r),live='minikPingPong/live/ABCDEF_0_0_1';
  await env.withSecurityRulesDisabled(c=>c.database().ref(live).set({checkpoint:{kind:'tournaments',code:r.code}}));
  await assertFails(db('alice').ref(live).remove());await assertSucceeds(db('alice').ref(p).remove());
  await assertSucceeds(db('alice').ref(live).remove());
});

test('character names reserve uniquely; removed words and free text are rejected',async()=>{
  for(const name of ['BestJune','HappyJune1','GreenMiniko','WinterCoach67','סהר בקיץ','מיניקו בירוק22']){
    await assertSucceeds(db('alice').ref(`minikPingPong/nicknames/${name}`).set('alice'));
    await assertFails(db('bob').ref(`minikPingPong/nicknames/${name}`).set('bob'));
  }
  for(const name of ['צפרדע ממוזלת','נמר ממוזל','JollyFrog','CozyCub','JuneAnything','<Flare>'])
    await assertFails(db('alice').ref(`minikPingPong/nicknames/${name}`).set('alice'));
});
test('human characters round-trip in profiles and active games without AI privileges',async()=>{
  await assertSucceeds(db('alice').ref('minikPingPong/nicknames/HappyJune').set('alice'));
  const profile={...identity('alice'),name:'HappyJune',characterId:'june'};
  await assertSucceeds(db('alice').ref('minikPingPong/profiles/alice').set(profile));
  await assertFails(db('alice').ref('minikPingPong/profiles/alice').set({...profile,characterId:'unknown'}));
  const p=await seed('friendlyRooms',playing(schedule(room())));
  await assertSucceeds(db('alice').ref(`${p}/participants/alice/identity`).set(profile));
  assert.equal((await read(`${p}/participants/alice`)).bot,undefined);
  await assertFails(db('bob').ref(`${p}/participants/alice/identity/characterId`).set('flare'));
  await assertFails(db('bob').ref(`${p}/participants/alice/identity/characterId`).remove());
  await assertFails(db('alice').ref(`${p}/participants/alice/bot`).set(bot));
  await assertFails(db('alice').ref(`${p}/participants/alice/identity/characterId`).set('unknown'));
  await assertSucceeds(db('alice').ref(`${p}/participants/alice/identity/characterId`).remove());
});

test('monetization codes and purchase records remain server-only for both apps',async()=>{
  for(const root of ['minikPingPong/monetization','minikMath/monetization']){
    await env.withSecurityRulesDisabled(c=>c.database().ref(root+'/codes/private').set({enabled:true,maxUses:1}));
    for(const uid of [null,'alice','bob']){
      for(const child of ['codes/private','purchases/fake','rate/fake']){
        await assertFails(db(uid).ref(root+'/'+child).once('value'));
        await assertFails(db(uid).ref(root+'/'+child).set({enabled:true,verifiedAt:Date.now()}));
      }
      await assertFails(db(uid).ref(root).once('value'));
      await assertFails(db(uid).ref(root).set({codes:{free:{enabled:true}}}));
    }
  }
});

test('Beginner control rooms are accepted and a one-point final margin is legal',async()=>{
  const r=room('friendlyRooms',['alice'],'ABCDEF',2);r.difficulty=4;
  await reserve('alice','friendlyRooms',r.code);
  await assertSucceeds(db('alice').ref('minikPingPong/friendlyRooms/ABCDEF').set(r));
  const active=playing(schedule(joined(r,'bob')));const p=await seed('friendlyRooms',active);
  const result=finish(active);result.matches.ABCDEF_0_0_1.scoreB=6;
  await assertFails(db('bob').ref(p).set(result));
  await assertSucceeds(db('alice').ref(p).set(result));
});
test('Sapir avatar nickname reserves uniquely while an owned legacy Kyra name remains valid',async()=>{
  await assertSucceeds(db('alice').ref('minikPingPong/nicknames/ספיר בכיף').set('alice'));
  await assertFails(db('bob').ref('minikPingPong/nicknames/ספיר בכיף').set('bob'));
  await env.withSecurityRulesDisabled(c=>c.database().ref('minikPingPong/nicknames/קשת בקיץ').set('alice'));
  await assertSucceeds(db('alice').ref('minikPingPong/nicknames/קשת בקיץ').set('alice'));
});


// Knockout: server validates stored draws, winners/byes and the same result authority.
function knockoutRoom(ids=['alice','bob'],capacity=ids.length) {
  return {...room('tournaments',ids,'KNCDEF',capacity),format:'KNOCKOUT'};
}
function knockoutDraw(r,ids,round=0) {
  r=clone(r);r.state='ACTIVE';r.rounds??={};r.matches??={};
  r.rounds[round]={count:ids.length,players:ids};
  for(let i=0;i<Math.floor(ids.length/2);i++) {
    const a=ids[i*2],b=ids[i*2+1],id=r.code+'_K'+round+'_'+i;
    const humans=[a,b].filter(x=>!r.participants[x].bot).sort();
    r.matches[id]={id,a,b,seed:123,phase:humans.length?'WAITING':'FINISHED',authorityUid:humans[0]||r.host,
      starts:0,scoreA:humans.length?0:7,scoreB:0,winner:humans.length?'':a};
  }
  return r;
}
function knockoutSettle(r) {
  r=clone(r);
  while(true) {
    const round=Math.max(...Object.keys(r.rounds).map(Number)),players=r.rounds[round].players;
    const matches=Array.from({length:Math.floor(players.length/2)},(_,i)=>r.matches[r.code+'_K'+round+'_'+i]);
    if(matches.some(m=>!['FINISHED','CANCELLED'].includes(m.phase)))return r;
    const ids=[...matches.map(m=>m.winner),...(players.length%2?[players.at(-1)]:[])]
      .filter(id=>id&&!r.departed?.[id]);
    if(ids.length<=1){r.state='FINISHED';return r;}
    r=knockoutDraw(r,ids.reverse(),round+1);
  }
}
function knockoutFinish(r,id,winner) {
  r=clone(r);const m=r.matches[id];m.phase='FINISHED';m.scoreA=winner===m.a?7:1;m.scoreB=winner===m.b?7:1;m.winner=winner;
  return knockoutSettle(r);
}

test('knockout: create and join nine-player room; round robin remains limited to eight',async()=>{
  const r=knockoutRoom(['alice'],9),p='minikPingPong/tournaments/KNCDEF';
  await reserve('alice','tournaments',r.code);await assertSucceeds(db('alice').ref(p).set(r));
  await reserve('bob','tournaments',r.code);await assertSucceeds(change('bob',p,r=>joined(r,'bob')));
  await assertFails(change('alice',p,r=>{delete r.format;return r}));
  const rr=room('tournaments',['alice'],'BCDXYZ',9);await reserve('alice','tournaments',rr.code,1);
  await assertFails(db('alice').ref('minikPingPong/tournaments/'+rr.code).set(rr));
  const friendly={...room('friendlyRooms',['alice'],'DEFXYZ',2),format:'KNOCKOUT'};
  await reserve('alice','friendlyRooms',friendly.code);
  await assertFails(db('alice').ref('minikPingPong/friendlyRooms/'+friendly.code).set(friendly));
});

test('knockout: host starts every size 2–9, with exactly one bye for odd counts',async()=>{
  for(let count=2;count<=9;count++){
    const ids=['alice','bob','charlie','dana','erin','frank','grace','hank','ivy'].slice(0,count);
    const r=knockoutRoom(ids),p=await seed('tournaments',r),next=knockoutSettle(knockoutDraw(r,ids.slice().reverse()));
    await assertFails(db('bob').ref(p).set(next));
    await assertSucceeds(db('alice').ref(p).set(next));
    assert.equal(Object.keys((await read(p)).matches).length,Math.floor(count/2));
  }
});

test('knockout: complete odd and even tournaments, advance exact winners plus bye, and keep results immutable',async()=>{
  for(const count of [2,3,5,8,9]){
    const ids=['alice','bob','charlie','dana','erin','frank','grace','hank','ivy'].slice(0,count);
    let r=knockoutRoom(ids);const p=await seed('tournaments',r);
    r=knockoutDraw(r,ids);await assertSucceeds(db('alice').ref(p).set(r));
    let completed=0;
    while(r.state!=='FINISHED'){
      const m=Object.values(r.matches).find(m=>m.phase==='WAITING');
      assert.ok(m);m.phase='PLAYING';m.starts=1;
      await seed('tournaments',r);
      const next=knockoutFinish(r,m.id,m.a);
      const nonAuthority=ids.find(id=>id!==m.authorityUid);
      await assertFails(db(nonAuthority).ref(p).set(next));
      await assertSucceeds(db(m.authorityUid).ref(p).set(next));
      await assertSucceeds(db(m.authorityUid).ref(p).set(next)); // retry is idempotent
      r=next;completed++;
    }
    assert.equal(completed,count-1);
    await assertFails(change('alice',p,r=>{r.state='ACTIVE';return r}));
    const id=Object.keys(r.matches)[0];
    await assertFails(change('alice',p,r=>{r.matches[id].scoreA=8;return r}));
    await assertFails(change('alice',p,r=>{delete r.rounds[0];return r}));
  }
});

test('knockout: invalid initial draws, extra matches and early rounds are rejected',async()=>{
  const r=knockoutRoom(['alice','bob','charlie','dana','erin']),p=await seed('tournaments',r);
  const good=knockoutDraw(r,Object.keys(r.participants));
  for(const alter of [
    n=>{n.rounds[0].players[4]='alice'},
    n=>{n.rounds[0].players[4]='outsider'},
    n=>{n.rounds[0].count=4;n.rounds[0].players.pop()},
    n=>{n.matches.extra=clone(Object.values(n.matches)[0]);n.matches.extra.id='extra'},
    n=>{delete n.matches.KNCDEF_K0_0}
  ]){const bad=clone(good);alter(bad);await assertFails(db('alice').ref(p).set(bad));}
  await assertSucceeds(db('alice').ref(p).set(good));
  await assertFails(db('alice').ref(p).set(knockoutDraw(good,['alice','charlie','erin'],1)));
  await assertFails(change('alice',p,r=>{r.rounds[0].players.reverse();return r}));
});

test('knockout: last result must carry next draw; cannot drop bye or advance eliminated/duplicate players',async()=>{
  let r=knockoutDraw(knockoutRoom(['alice','bob','charlie','dana','erin']),['alice','bob','charlie','dana','erin']);
  Object.values(r.matches).forEach(m=>{m.phase='PLAYING';m.starts=1});
  r=knockoutFinish(r,'KNCDEF_K0_0','alice');
  const p=await seed('tournaments',r),good=knockoutFinish(r,'KNCDEF_K0_1','charlie');
  const noDraw=clone(good);delete noDraw.rounds[1];delete noDraw.matches.KNCDEF_K1_0;
  await assertFails(db('charlie').ref(p).set(noDraw));
  for(const ids of [['alice','charlie'],['bob','charlie','erin'],['alice','alice','erin'],['alice','charlie','outsider']]){
    let bad=clone(noDraw);bad=knockoutDraw(bad,ids,1);
    await assertFails(db('charlie').ref(p).set(bad));
  }
  await assertFails(db('eve').ref(p).set(good));
  await assertSucceeds(db('charlie').ref(p).set(good));
  await assertFails(change('alice',p,r=>{delete r.matches.KNCDEF_K0_0;return r}));
});

test('knockout: house-player fixtures and cascading rounds settle atomically after a human loses',async()=>{
  let r=knockoutRoom(['alice','bot_flare','bot_kyra','bot_mia','bot_gaya']);
  for(const [id,p] of Object.entries(r.participants))if(p.bot)p.bot.characterId=id.slice(4);
  const p=await seed('tournaments',r);
  r=knockoutSettle(knockoutDraw(r,['alice','bot_flare','bot_kyra','bot_mia','bot_gaya']));
  await assertSucceeds(db('alice').ref(p).set(r));
  r.matches.KNCDEF_K0_0.phase='PLAYING';r.matches.KNCDEF_K0_0.starts=1;
  await seed('tournaments',r);
  const next=knockoutFinish(r,'KNCDEF_K0_0','bot_flare');
  assert.equal(next.state,'FINISHED');assert.equal(Object.keys(next.matches).length,4);
  await assertSucceeds(db('alice').ref(p).set(next));
});

test('knockout: quitting awards an honest walkover and transfers host; invented walkovers rejected',async()=>{
  let r=knockoutDraw(knockoutRoom(['alice','bob','charlie']),['alice','bob','charlie']);
  r.connections={alice:{0:true},bob:{0:true},charlie:{0:true}};
  const p=await seed('tournaments',r);
  const next=clone(r);next.departed={alice:true};next.host='bob';delete next.connections.alice;
  Object.assign(next.matches.KNCDEF_K0_0,{phase:'CANCELLED',winner:'bob'});
  const good=knockoutSettle(next);
  const bad=clone(good);delete bad.departed;
  await assertFails(db('alice').ref(p).set(bad));
  await assertSucceeds(db('alice').ref(p).set(good));
  assert.deepEqual(new Set((await read(p)).rounds[1].players),new Set(['bob','charlie']));
});

test('knockout: a bye may repeat next round, but results cannot be rewritten to choose it later',async()=>{
  let r=knockoutDraw(knockoutRoom(['alice','bob','charlie','dana','erin']),['alice','bob','charlie','dana','erin']);
  Object.values(r.matches).forEach(m=>{m.phase='PLAYING';m.starts=1});
  r=knockoutFinish(r,'KNCDEF_K0_0','alice');
  const p=await seed('tournaments',r);
  const good=knockoutFinish(r,'KNCDEF_K0_1','charlie');
  const sameBye=knockoutDraw(good,['alice','charlie','erin'],1);
  await assertSucceeds(db('charlie').ref(p).set(sameBye));
  await assertFails(db('alice').ref(p).set(good)); // draw frozen after commit
});

for(const kind of ['friendlyRooms','tournaments'])for(const arena of ['beach','indoors','park','castle']) {
 test(`${kind}: ${arena} survives joining and is immutable`,async()=>{
  const r={...room(kind,['alice'],'ARENA2',2),arena},p=`minikPingPong/${kind}/${r.code}`;
  await reserve('alice',kind,r.code);await reserve('bob',kind,r.code);
  await assertSucceeds(db('alice').ref(p).set(r));
  await assertSucceeds(change('bob',p,r=>joined(r,'bob')));
  assert.equal((await read(p)).arena,arena);
  for(const who of ['alice','bob']){
   await assertFails(db(who).ref(p+'/arena').set(arena==='park'?'beach':'park'));
   await assertFails(db(who).ref(p+'/arena').remove());
  }
  await assertSucceeds(db('alice').ref(p).set(schedule(await read(p))));
  assert.equal((await read(p)).arena,arena);
 });
}
test('unknown arena is rejected when creating a room',async()=>{
 const r={...room('friendlyRooms',['alice'],'ARENA3',2),arena:'other-app'};
 await reserve('alice','friendlyRooms',r.code);
 await assertFails(db('alice').ref('minikPingPong/friendlyRooms/'+r.code).set(r));
});

test('rank points use the existing own profile; another player can read but cannot write',async()=>{
 await assertSucceeds(db('alice').ref('minikPingPong/nicknames/GreenFrog').set('alice'));
 await assertSucceeds(db('alice').ref('minikPingPong/profiles/alice').set({...identity('alice'),name:'GreenFrog',rankPoints:100,rankLevel:0}));
 await assertSucceeds(db('alice').ref('minikPingPong/profiles/alice/rankPoints').transaction(n=>Math.max(n||0,250)));
 assert.equal((await db('bob').ref('minikPingPong/profiles/alice/rankPoints').once('value')).val(),250);
 await assertSucceeds(db('alice').ref('minikPingPong/profiles/alice/rankLevel').set(1));
 await assertFails(db('bob').ref('minikPingPong/profiles/alice/rankLevel').set(11));
 await assertFails(db('bob').ref('minikPingPong/profiles/alice/rankPoints').set(999));
 await assertFails(db().ref('minikPingPong/profiles/alice/rankPoints').once('value'));
});
test('replay may create a fresh friendly room with the same house player',async()=>{
 const r=room('friendlyRooms',['alice','bot_kyra'],'RPLABC',2);r.target=11;r.arena='park';
 await reserve('alice','friendlyRooms',r.code);
 await assertSucceeds(db('alice').ref('minikPingPong/friendlyRooms/'+r.code).set(r));
});
