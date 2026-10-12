/* Android-only bridge; no ads or new SDKs on the website. */
(()=>{
  const native=window.MinikAdsNative, pending=new Map();let sequence=0,activity=()=>false;
  let prepared=false;
  const api={
    begin(kind){return kind+'/'+(globalThis.crypto?.randomUUID?.() || Date.now().toString(36)+'-'+Math.random().toString(36).slice(2));},
    finish(id,callback){
      if(!native){callback();return;}
      window.MinikAudio?.stopAll();native.playing(false);
      const token=String(++sequence);pending.set(token,callback);
      // A modal blocks rapid Next/Start taps during the completed-activity boundary.
      const mask=document.createElement('div');mask.id='minik-ad-boundary';mask.setAttribute('role','status');
      Object.assign(mask.style,{position:'fixed',inset:'0',zIndex:'2147483647',display:'grid',placeItems:'center',background:'#f8f5ff',color:'#282d4e',fontSize:'24px',fontWeight:'bold'});
      mask.textContent=document.documentElement.lang==='he'?'הסבב הסתיים':'Round finished';document.body.append(mask);
      native.finish(id,token);
    },
    complete(token){const callback=pending.get(String(token));if(!callback)return;pending.delete(String(token));document.getElementById('minik-ad-boundary')?.remove();callback();},
    track(getter){activity=getter;},
    menu(parent,lang){
      if(!native)return;
      const b=document.createElement('button');b.type='button';b.textContent=lang==='he'?'להורים · הסרת פרסומות':'Parents · Remove ads';
      Object.assign(b.style,{display:'block',margin:'20px auto',padding:'12px 20px',minHeight:'48px',color:'#e91e63',background:'transparent',border:'0',fontWeight:'bold'});
      b.onclick=()=>native.settings(lang);parent.append(b);
    }
  };
  window.MinikMonetization=api;
  if(native){
    setInterval(()=>{
      const active=!document.hidden && pending.size===0 && !!activity();native.playing(active);
      if(!active && !document.hidden && !prepared && !pending.size){prepared=true;native.prepare();}
    },1000);
    document.addEventListener('visibilitychange',()=>{if(document.hidden)native.playing(false);else prepared=false;});
    window.addEventListener('pagehide',()=>native.playing(false));
  }
})();
