// iOS mirror of MinikCrossPong firebase/tests/configuration.test.cjs (828c6fc). Static checks of the iOS client's
// namespace and Firebase app registration, the merged rules candidate and this folder's emulator wiring. The Android
// production-config check is not mirrored: nothing in the iOS repository deploys rules.
const {test}=require('node:test');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const here=path.resolve(__dirname,'..');
const repo=path.resolve(here,'../..');
const local=p=>fs.readFileSync(path.join(here,p),'utf8');
test('the iOS client uses its own Cross Pong registration and only the minikCrossPong namespace',()=>{
  const repository=fs.readFileSync(path.join(repo,'MultiPong/MPRepository.swift'),'utf8');
  assert.ok(repository.includes('database.reference().child("minikCrossPong")'));
  assert.ok(repository.includes('"minik-cross-pong"'));
  assert.ok(repository.includes('"com.appsbybros.minik.crosspong"'));
  for(const other of ['child("minikPingPong")','child("tripleShot")','"minik-ping-pong"'])assert.ok(!repository.includes(other),other);
});
test('rules candidate keeps the root closed and adds the Cross Pong subtree without a leaderboard',()=>{
  const rules=JSON.parse(local('rules/merged.json'));
  assert.equal(rules.rules['.read'],false);assert.equal(rules.rules['.write'],false);
  assert.ok(rules.rules.minikCrossPong&&rules.rules.minikPingPong&&rules.rules.tripleShot);
  assert.equal(rules.rules.minikCrossPong.leaderboard,undefined);
});
test('the emulator configuration loads the exact merged candidate on 127.0.0.1 under the demo project',()=>{
  const emulator=JSON.parse(local('firebase.json'));
  assert.equal(emulator.database.rules,'rules/merged.json');
  assert.equal(emulator.emulators.database.host,'127.0.0.1');
  assert.ok(JSON.parse(local('package.json')).scripts['test:emulator'].includes('--project demo-minik-crosspong'));
});
// Android cae4ee6.
test('combined candidate includes both games and both teams ball-assistance preferences',()=>{
 const rules=JSON.parse(local('rules/merged.json')).rules;
 for(const name of ['minikPingPong','minikCrossPong','minikPongTeams','minikCrossTeams']){
  assert.ok(rules[name].receptionPreferences?.$uid?.slow,name+' missing preference validation');
 }
});
