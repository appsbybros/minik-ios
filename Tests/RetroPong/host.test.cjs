'use strict';
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const {test} = require('node:test'), assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname, '../../Resources/RetroPong/ios-host.js'), 'utf8');
const key = 'minik.pong.progress.v1';
function host(config = {}, quota = false, extra = {}) {
  class Storage {
    constructor() { this.map = new Map(); }
    getItem(k) { return this.map.get(k) ?? null; }
    setItem(k, v) { if (quota) throw new Error('QuotaExceededError'); this.map.set(k, String(v)); }
  }
  const messages = [], pauses = [], events = new Map(); let stops = 0, exits = 0, sessionStops = 0, setups = 0;
  const classes = new Map(), timers = [];
  const c = {Storage, localStorage:new Storage(), sessionStorage:new Storage(), __minikRetroConfig:config,
    webkit:{messageHandlers:{retroPong:{postMessage:m=>messages.push(m)}}},
    document:{documentElement:{classList:{toggle:(name,value)=>classes.set(name,value)}},addEventListener:(name,fn)=>events.set(name,fn)},
    PongExtras:{nativePause:value=>pauses.push(value)}, MinikAudio:{stopAll:()=>stops++}, exitPong:()=>exits++, stopPongSession:()=>sessionStops++,returnToPongSetup:()=>setups++,
    setTimeout:fn=>{timers.push(fn);return timers.length;}};
  Object.assign(c,extra); c.window=c; vm.runInNewContext(source,c);
  return {c,messages,pauses,classes,timers,ready:()=>events.get('DOMContentLoaded')(),get stops(){return stops;},get exits(){return exits;},get sessionStops(){return sessionStops;},get setups(){return setups;}};
}
test('Native progress seeds the game before it boots and only Pong is mirrored',()=>{
  const h=host({language:'he',state:{version:1,points:700}});
  assert.equal(JSON.parse(h.c.localStorage.getItem(key)).points,700);
  h.c.localStorage.setItem('math-progress','unchanged');
  h.c.sessionStorage.setItem(key,'session only');
  assert.equal(h.messages.length,0);
  h.c.localStorage.setItem(key,JSON.stringify({version:1,points:701}));
  assert.equal(h.messages.length,1); assert.equal(h.messages[0].type,'save');
  assert.equal(JSON.parse(h.messages[0].state).points,701);
  assert.equal(h.c.localStorage.getItem('math-progress'),'unchanged');
  assert.equal(h.c.sessionStorage.getItem(key),'session only');
  assert.equal(h.c.MinikRetroHost.language,'he');
});
test('Native mirror keeps working if WebKit storage refuses a write',()=>{
  const h=host({state:{points:99}},true);
  h.c.localStorage.setItem(key,'{"points":100}');
  assert.equal(JSON.parse(h.c.localStorage.getItem(key)).points,100);
  assert.equal(h.messages[0].state,'{"points":100}');
  assert.throws(()=>h.c.localStorage.setItem('unrelated','x'),/Quota/);
});
test('Paused launch and later foreground/background events control the game clock and audio',()=>{
  const h=host({paused:true,language:'en'});h.ready();
  assert.deepEqual(h.pauses,[true]); assert.equal(h.stops,1);
  h.c.MinikRetroHost.setActive(true);h.c.MinikRetroHost.setActive(false);
  assert.deepEqual(h.pauses,[true,false,true]);assert.equal(h.stops,2);
});
test('An early lifecycle update survives until game boot',()=>{
  const h=host(); h.c.MinikRetroHost.setActive(false); h.ready();
  assert.deepEqual(h.pauses,[true,true]);
});
test('Embedded Back cleans up and returns to Math exactly once, without a closed screen',()=>{
  const h=host({canExit:true});h.ready();h.c.exitPong();h.c.exitPong();
  assert.equal(h.sessionStops,1);assert.equal(h.stops,1);assert.equal(h.exits,0);
  assert.deepEqual(h.messages.map(x=>x.type),['music','exit']);assert.equal(h.setups,0);
  assert.equal(h.classes.get('minik-ios-standalone'),false);
});
test('Standalone Back returns to setup, hides root Exit, and never requests app termination',()=>{
  const h=host();h.ready();h.c.exitPong();
  assert.equal(h.sessionStops,1);assert.equal(h.setups,1);assert.equal(h.exits,0);
  assert.equal(h.messages.some(x=>x.type==='exit'),false);
  assert.equal(h.classes.get('minik-ios-standalone'),true);
});
test('Menu music only sends commands to the single native player',()=>{
  const h=host();h.c.PongMusic.start();h.c.PongMusic.stop();
  assert.deepEqual(h.messages.map(x=>[x.type,x.playing]),[['music',true],['music',false]]);
});
test('Unknown language falls back to game selection, unsupported bridge remains harmless',()=>{
  const h=host({language:'not-a-language'}); assert.equal(h.c.MinikRetroHost.language,null);
  delete h.c.webkit; h.c.localStorage.setItem(key,'{"points":4}');h.c.PongMusic.start();
  assert.equal(h.c.localStorage.getItem(key),'{"points":4}');
});
test('Without a native ad host the saved result shows at once and no parents link appears',()=>{
  const h=host(); let shown=0;
  h.c.MinikMonetization.finish('paddle/1',()=>shown++);
  assert.equal(shown,1); assert.equal(h.messages.length,0);
  assert.equal(h.c.MinikMonetization.menu({}, 'en'),null);
});
test('Standalone Bounce waits for the native ad boundary, then shows the result exactly once',()=>{
  const h=host({monetization:true}); let shown=0;
  const id=h.c.MinikMonetization.begin('paddle');
  assert.match(id,/^paddle\//);
  h.c.MinikMonetization.finish(id,()=>shown++);
  assert.equal(shown,0); assert.equal(h.stops,1);
  assert.deepEqual(h.messages.map(x=>[x.type,x.id,x.token]),[['matchFinished',id,'1']]);
  h.c.MinikMonetization.complete('1'); h.c.MinikMonetization.complete('1');
  assert.equal(shown,1);
  h.timers.forEach(fn=>fn()); assert.equal(shown,1);
});
test('A host that never answers cannot strand the result screen',()=>{
  const h=host({monetization:true}); let shown=0;
  h.c.MinikMonetization.finish('paddle/2',()=>shown++);
  assert.equal(shown,0); h.timers.forEach(fn=>fn()); assert.equal(shown,1);
});
test('App Store capture scenes stage progress in memory, start the game and never save',()=>{
  const loads=[];let resets=0;
  const h=host({state:{version:1,points:5}},false,{MinikScreenshotScene:'train',addEventListener:(name,fn)=>loads.push([name,fn]),resetPong:()=>resets++});
  const staged=JSON.parse(h.c.localStorage.getItem(key));
  assert.equal(staged.points,1280); assert.equal(staged.levels.addition,12); assert.equal(staged.trainMode,'tap');
  h.c.localStorage.setItem(key,JSON.stringify({version:1,points:1281}));
  assert.equal(h.messages.length,0); assert.equal(h.c.localStorage.map.get(key),undefined);
  assert.equal(loads.length,1); assert.equal(loads[0][0],'load');
  loads[0][1](); h.timers.at(-1)(); assert.equal(resets,1);
});
test('Unknown capture scene names change nothing',()=>{
  const h=host({state:{version:1,points:5}},false,{MinikScreenshotScene:'toString'});
  assert.equal(JSON.parse(h.c.localStorage.getItem(key)).points,5);
  h.c.localStorage.setItem(key,JSON.stringify({version:1,points:6}));
  assert.equal(h.messages.length,1);
});
test('The idle setup with the parents link asks the native host for the family reminder, as Android Bounce does',()=>{
  const intervals=[], panel={isConnected:true,style:{},append(){},querySelectorAll:()=>[],getClientRects:()=>[{}]};
  let visibility='visible', playing=false;
  const h=host({monetization:true,parents:true},false,{
    setInterval:(fn,ms)=>{intervals.push([fn,ms]);return intervals.length;},
    getComputedStyle:()=>({position:'relative',visibility}),requestAnimationFrame:()=>0});
  h.c.document.createElement=()=>({style:{},setAttribute(){}}); h.c.document.hidden=false;
  h.c.MinikMonetization.track(()=>playing);
  assert.notEqual(h.c.MinikMonetization.menu(panel,'en'),null);
  h.c.MinikMonetization.menu(panel,'en');
  assert.equal(intervals.length,1); assert.equal(intervals[0][1],1000);
  const idle=()=>{h.messages.length=0;intervals[0][0]();return h.messages.filter(x=>x.type==='menuIdle').length;};
  assert.equal(idle(),1);
  playing=true; assert.equal(idle(),0); playing=false;
  visibility='hidden'; assert.equal(idle(),0); visibility='visible';
  panel.getClientRects=()=>[]; assert.equal(idle(),0); panel.getClientRects=()=>[{}];
  h.c.MinikRetroHost.setActive(false); assert.equal(idle(),0); h.c.MinikRetroHost.setActive(true);
  h.c.MinikMonetization.finish('paddle/3',()=>{}); assert.equal(idle(),0);
  h.c.MinikMonetization.complete('1'); assert.equal(idle(),1);
});
test('Math, with no parents link, never asks for the family reminder',()=>{
  const intervals=[];
  const h=host({monetization:true},false,{setInterval:fn=>{intervals.push(fn);return 1;}});
  assert.equal(h.c.MinikMonetization.menu({style:{}},'en'),null);
  assert.equal(intervals.length,0);
});
