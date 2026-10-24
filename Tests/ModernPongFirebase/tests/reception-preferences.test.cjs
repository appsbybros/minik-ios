const {test,before,after}=require('node:test');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {initializeTestEnvironment,assertSucceeds:yes,assertFails:no}=require('@firebase/rules-unit-testing');
let env;
before(async()=>{
 assert.match(process.env.FIREBASE_DATABASE_EMULATOR_HOST||'',/^127\.0\.0\.1:[0-9]+$/,'Explicit local emulator required; never use production');
 env=await initializeTestEnvironment({projectId:'demo-reception-preferences',database:{host:'127.0.0.1',port:Number(process.env.FIREBASE_DATABASE_EMULATOR_HOST.split(':')[1]),rules:fs.readFileSync(path.resolve(__dirname,'../rules/merged.json'),'utf8')}});
 await env.clearDatabase();
});
after(async()=>{if(env)await env.cleanup()});
for(const root of ['minikPingPong','minikCrossPong','minikPongTeams','minikCrossTeams']){
 test(root+': own preferences round-trip; other players and malformed writes denied',async()=>{
  const own=env.authenticatedContext('alice').database().ref(root+'/receptionPreferences/alice');
  const peer=env.authenticatedContext('bob').database().ref(root+'/receptionPreferences/alice');
  const anon=env.unauthenticatedContext().database().ref(root+'/receptionPreferences/alice');
  for(const slow of [true,false]){
   await yes(own.set({version:1,slow}));
   assert.deepEqual((await yes(peer.once('value'))).val(),{version:1,slow});
  }
  await no(peer.set({version:1,slow:true}));
  await no(peer.remove());
  await no(anon.set({version:1,slow:true}));
  await no(anon.once('value'));
  for(const invalid of [{slow:true},{version:2,slow:true},{version:1,slow:'true'},{version:1,slow:true,zoom:true}])await no(own.set(invalid));
  await yes(own.remove());
 });
}
