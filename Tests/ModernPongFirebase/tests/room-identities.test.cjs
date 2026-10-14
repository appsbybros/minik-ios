const fs=require('node:fs'),test=require('node:test'),assert=require('node:assert/strict'),{createRequire}=require('node:module');
const req=require;
const {initializeTestEnvironment,assertSucceeds:yes,assertFails:no}=req('@firebase/rules-unit-testing');
const {ref,set,get,update,remove,serverTimestamp}=req('firebase/database');
let env;const db=u=>env.authenticatedContext(u).database();
test.before(async()=>{assert.match(process.env.FIREBASE_DATABASE_EMULATOR_HOST||'',/^127\.0\.0\.1:[0-9]+$/,'Explicit local emulator required');env=await initializeTestEnvironment({projectId:'demo-minikpongteams-identity',database:{host:'127.0.0.1',port:Number(process.env.FIREBASE_DATABASE_EMULATOR_HOST.split(':')[1]),rules:fs.readFileSync(__dirname+'/../rules/pong-team.json','utf8')}});await env.clearDatabase()});
test.after(async()=>env.cleanup());
for(const [node,protocol,mode,guestSeat]of[['minikPongTeams', 'pong-doubles-v1', 'ALTERNATE', 2]]){
 const root=node+'/rooms/QA2345';
 const value=()=>({meta:{host:'host',protocol,mode,humans:{0:true,[guestSeat]:true},roster:['miniko','minik','mia','june'],createdAt:serverTimestamp()},phase:'lobby',seats:{0:'host'},ready:{host:false}});
 test(node+': own identity, automatic handshake, cancellation and authority boundaries',async()=>{
  await yes(set(ref(db('host'),root),value()));
  await no(get(ref(env.unauthenticatedContext().database(),root)));
  await no(remove(ref(db('stranger'),root)));
  await no(set(ref(db('stranger'),root+'/profiles/stranger'),{name:'X',character:'flare'}));
  await yes(set(ref(db('guest'),root+'/seats/'+guestSeat),'guest'));
  for(const [user,name,character]of[['host','Sahar','miniko'],['guest','Dana','gaya']]){
   await yes(set(ref(db(user),root+'/profiles/'+user),{name,character}));
   await yes(set(ref(db(user),root+'/ready/'+user),true));
  }
  await no(set(ref(db('host'),root+'/profiles/guest'),{name:'Spoof',character:'flare'}));
  await yes(update(ref(db('guest'),root+'/profiles/guest'),{teammate:'flare'}));
  await no(update(ref(db('host'),root+'/profiles/guest'),{teammate:'kyra'}));
  await no(update(ref(db('guest'),root+'/profiles/guest'),{teammate:'unknown'}));
  await no(set(ref(db('guest'),root+'/profiles/guest'),{name:'',character:'gaya'}));
  await no(set(ref(db('guest'),root+'/profiles/guest'),{name:'Dana',character:'not-a-character'}));
  await no(remove(ref(db('guest'),root)));
  const snapshot={body:JSON.stringify({protocol}),at:serverTimestamp()};
  await no(update(ref(db('host'),root),{phase:'playing',snapshot}));
  // A guest can cancel without deleting the host or a friend's identity.
  await yes(update(ref(db('guest'),root),{['seats/'+guestSeat]:null,'profiles/guest':null,'ready/guest':null,'presence/guest':null}));
  assert.equal((await get(ref(db('host'),root+'/seats/0'))).val(),'host');
  await yes(set(ref(db('guest'),root+'/seats/'+guestSeat),'guest'));
  await yes(set(ref(db('guest'),root+'/profiles/guest'),{name:'Dana',character:'gaya'}));await yes(set(ref(db('guest'),root+'/ready/guest'),true));
  for(const u of ['host','guest'])await yes(set(ref(db(u),root+'/presence/'+u),serverTimestamp()));
  await no(update(ref(db('guest'),root),{phase:'playing',snapshot}));
  await yes(update(ref(db('host'),root),{phase:'playing',snapshot}));
  await no(remove(ref(db('host'),root))); // Cancel may never erase a started match.
  await no(remove(ref(db('guest'),root+'/seats/'+guestSeat)));
  await no(set(ref(db('guest'),root+'/profiles/guest'),{name:'Changed mid-match',character:'flare'}));
  const other=root.replace('QA2345','QA2346');await yes(set(ref(db('host'),other),value()));await yes(remove(ref(db('host'),other)));
  assert.equal((await get(ref(db('host'),other))).exists(),false);
 });
}
