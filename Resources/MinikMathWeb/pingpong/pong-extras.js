/* MINIK v43: local progression, selectable controls, and the passing math train.
   No network, accounts, telemetry, or changes to the Pong match-score rules. */
(() => {
  "use strict";
  const STORAGE_KEY = "minik.pong.progress.v1";
  const ROOT = "assets/expansion/";
  const SKINS = [
    {name:"yellow",at:0}, {name:"red",at:100}, {name:"green",at:200}, {name:"blue",at:300},
    {name:"red_with_border",at:500}, {name:"green_with_border",at:700},
    {name:"blue_with_border",at:900}, {name:"silver_with_border",at:1200}
  ];
  const OPS = ["addition","subtraction","multiply","divide"];
  const COPY = {
    en:{title:"Ready to play?",settings:"Help & settings",intro:"Keep the ball in play, collect points, and level up your paddle and arrows!",
      controls:"Paddle controls",arrows:"On-screen arrows",keyboard:"Keyboard",mouse:"Mouse",swipe:"Swipe",
      arrowsHelp:"Hold an arrow to move your paddle. On a keyboard, use the arrow keys too.",
      touchArrowsHelp:"Hold an arrow or slide your finger left and right on the paddle to move it. Lift your finger to stop.",
      keyboardHelp:"Use the keyboard arrow keys to move your paddle.",mouseHelp:"Move the mouse over the game to move your paddle.",
      swipeHelp:"Slide your finger over the game to move your paddle.",axisHelp:"In side-to-side games, the controls move up and down instead.",
      total:"Total points",totalShort:"Total",skins:"Level up your paddle and arrows",arrowRandom:"Your paddle and arrows always show your highest unlocked rank. Collect points to earn the next color. Higher ranks make both paddles narrower and your movement slightly faster.",available:"Unlocked",current:"Current",points:"points",toGo:"to go",
      storageWarning:"Storage is unavailable. Points and settings will last only for this visit.",
      scoring:"Points from the train and Balloon Madness are added only to your total points and do not change the match score.",
      train:"The question train",trainHelp:"Tap an answer wagon. With Balloon Madness on, the ball bounces off the train; with it off, the ball passes through. Ball hits never answer. The train returns 15 seconds after it leaves. Missing it has no penalty.",
      trainMode:"Answer the train with",tapMode:"Tap a wagon",offMode:"No train",
      tapHelp:"Tap the answer once per train: +3 if correct. See the answers, then the train speeds away. Balloon Madness on: the ball rebounds from the train. Off: it passes through. Ball hits never answer or score.",
      offHelp:"No train will appear. Your points and saved difficulty levels are kept.",
      adaptive:"A correct answer makes the next question harder; a wrong answer makes it easier. Your level is saved for next time.",
      operation:"Train operation",difficulty:"Train difficulty",example:"Example",addition:"Add +",subtraction:"Subtract −",multiply:"Multiply ×",divide:"Divide ÷",
      match:"Match settings",ai:"Minik level:",target:"Score to win",madness:"Balloon Madness",yes:"Yes",no:"No",
      play:"Start game",resume:"Resume game",close:"Back",correct:"Correct! +3 total points",incorrect:"Correct answer:",unlocked:"New arrows unlocked!",trainLabel:"Question train",trainAnswer:"Answer",easy:"Easy",hard:"Hard",
      yellow:"Yellow",red:"Red",green:"Green",blue:"Blue",red_with_border:"Framed red",green_with_border:"Framed green",blue_with_border:"Framed blue",silver_with_border:"Silver / gold"},
    he:{title:"מוכנים לשחק?",settings:"עזרה והגדרות",intro:"מחזירים את הכדור, צוברים נקודות ועולים בדרגת המחבט והחיצים!",
      controls:"שליטה במחבט",arrows:"חיצים על המסך",keyboard:"מקלדת",mouse:"עכבר",swipe:"החלקה",
      arrowsHelp:"לוחצים לחיצה ממושכת על חץ כדי להזיז את המחבט. אפשר גם להשתמש בחיצי המקלדת.",
      touchArrowsHelp:"מחזיקים חץ או מחליקים את האצבע ימינה ושמאלה על המחבט כדי להזיז אותו. מרימים את האצבע כדי לעצור.",
      keyboardHelp:"מזיזים את המחבט בעזרת חיצי המקלדת.",mouseHelp:"מזיזים את העכבר על המגרש כדי להזיז את המחבט.",
      swipeHelp:"מחליקים את האצבע על המגרש כדי להזיז את המחבט.",axisHelp:"במשחק מצד לצד, החיצים מזיזים את המחבט למעלה ולמטה.",
      total:"נקודות מצטברות",totalShort:"מצטבר",skins:"עלו בדרגת המחבט והחיצים",arrowRandom:"המחבט והחיצים שלכם מציגים תמיד את הדרגה הגבוהה ביותר שפתחתם. צברו נקודות כדי להגיע לצבע הבא. בכל דרגה שני המחבטים נעשים צרים יותר והתנועה שלכם מעט מהירה יותר.",available:"פתוח",current:"בשימוש",points:"נקודות",toGo:"נותרו",
      storageWarning:"השמירה אינה זמינה. הנקודות וההגדרות יישמרו רק עד סיום הביקור הנוכחי.",
      scoring:"נקודות מהרכבת ומטירוף הבלונים מתווספות רק לניקוד המצטבר ואינן משנות את תוצאת המשחק.",
      train:"רכבת השאלות",trainHelp:"לוחצים על קרון התשובה. בטירוף הבלונים הכדור קופץ מהרכבת; כשהאפשרות כבויה, הוא עובר דרכה. הכדור אינו עונה. הרכבת חוזרת 15 שניות אחרי שיצאה. לא הספקתם? אין קנס.",
      trainMode:"איך עונים לרכבת?",tapMode:"לחיצה על קרון",offMode:"ללא רכבת",
      tapHelp:"לוחצים פעם אחת על תשובה: תשובה נכונה מזכה ב־3 נקודות. הרכבת מציגה את התשובות ומאיצה החוצה. בטירוף הבלונים הכדור קופץ מהרכבת; כשהאפשרות כבויה, הוא עובר דרכה. הכדור אינו עונה ואינו צובר נקודות.",
      offHelp:"הרכבת לא תופיע. הנקודות ורמות הקושי שצברתם נשמרות.",
      adaptive:"תשובה נכונה מקשה מעט את השאלה הבאה, ותשובה שגויה מקלה עליה. הרמה נשמרת גם לפעם הבאה.",
      operation:"פעולת החשבון ברכבת",difficulty:"רמת קושי לרכבת",example:"לדוגמה",addition:"חיבור +",subtraction:"חיסור −",multiply:"כפל ×",divide:"חילוק ÷",
      match:"הגדרות המשחק",ai:"הרמה של מיניק:",target:"ניקוד לניצחון",madness:"טירוף בלונים",yes:"כן",no:"לא",
      play:"התחלת משחק",resume:"חזרה למשחק",close:"חזרה",correct:"נכון! נוספו 3 נקודות למצטבר",incorrect:"התשובה הנכונה:",unlocked:"נפתחו חיצים חדשים!",trainLabel:"רכבת השאלות",trainAnswer:"תשובה",easy:"קל",hard:"קשה",
      yellow:"צהוב",red:"אדום",green:"ירוק",blue:"כחול",red_with_border:"אדום עם מסגרת",green_with_border:"ירוק עם מסגרת",blue_with_border:"כחול עם מסגרת",silver_with_border:"כסף / זהב"}
  };
  const tr = key => COPY[typeof lang!=="undefined" && lang==="he"?"he":"en"][key] || key;
  const clamp = (v,a,b) => Math.min(b,Math.max(a,v));
  const int = (a,b) => a+Math.floor(Math.random()*(b-a+1));
  const shuffle = a => { for(let i=a.length-1;i>0;i--){const j=int(0,i);[a[i],a[j]]=[a[j],a[i]];} return a; };
  const safeLevel = n => Number.isInteger(n) ? clamp(n,1,12) : 1;
  const fresh = () => ({version:1,points:0,operation:"addition",levels:{addition:1,subtraction:1,multiply:1,divide:1},controlDesktop:"arrows",controlTouch:"arrows",trainMode:"tap",opponentDifficulty:"beginner",targetScore:5,balloonMadness:null});
  let storageAvailable=true, state=fresh();
  try{
    const raw=JSON.parse(localStorage.getItem(STORAGE_KEY)||"null");
    if(raw && raw.version===1){
      state.points=Number.isSafeInteger(raw.points)&&raw.points>=0 ? raw.points : 0;
      state.operation=OPS.includes(raw.operation)?raw.operation:"addition";
      // Migrate legacy ball-answer mode without resetting points or arithmetic levels.
      state.trainMode=raw.trainMode==="off"?"off":"tap";
      if(["beginner","medium","hard"].includes(raw.opponentDifficulty)) state.opponentDifficulty=raw.opponentDifficulty;
      if([3,5,7,11].includes(raw.targetScore))state.targetScore=raw.targetScore;
      if(typeof raw.balloonMadness==="boolean")state.balloonMadness=raw.balloonMadness;
      for(const op of OPS) state.levels[op]=safeLevel(raw.levels?.[op]);
      if(["arrows","keyboard","mouse"].includes(raw.controlDesktop)) state.controlDesktop=raw.controlDesktop;
      if(["arrows","swipe"].includes(raw.controlTouch)) state.controlTouch=raw.controlTouch;
    }
  }catch(_){storageAvailable=false;}
  function save(){try{localStorage.setItem(STORAGE_KEY,JSON.stringify(state));storageAvailable=true;}catch(_){storageAvailable=false;} updateStorageNote();}
  function setDifficulty(level){
    if(!["beginner","medium","hard"].includes(level))return;
    state.opponentDifficulty=level;save();
  }
  const mobile = () => typeof isPongMobileDevice==="function" && isPongMobileDevice();
  const control = () => androidApp()?"arrows":mobile()?state.controlTouch:state.controlDesktop;
  const skinFor = points => SKINS.reduce((best,s)=>points>=s.at?s:best,SKINS[0]);
  const androidApp=()=>/MinikNative\/Android/i.test(navigator.userAgent||"");
  const RANK_COLORS=["#ffd84d","#ef5350","#69d8a8","#4da3ff","#ef5350","#69d8a8","#4da3ff","#d7dee8"];
  const paddleRank=()=>androidApp()?SKINS.findIndex(s=>s.name===skinFor(state.points).name):0;
  const paddleColor=()=>androidApp()?RANK_COLORS[paddleRank()]:null;
  function prepareRound(){return paddleRank();}
  const paddleLengthFactor=()=>androidApp()?2.5-(2*paddleRank()/7):1;
  const paddleSpeedFactor=()=>androidApp()?1+0.04*paddleRank():1;
  function setMatchSettings(next){
    if([3,5,7,11].includes(next.targetScore))state.targetScore=next.targetScore;
    if(typeof next.balloonMadness==="boolean")state.balloonMadness=next.balloonMadness;
    save();
  }
  function syncPaddleRank(){
    if(!androidApp()||typeof pong==="undefined"||!pong)return;
    const length=resolvedPongPaddleHeight(pong.c),old=pong.paddleHeight;
    if(length!==old){
      const axis=pong.pcVertical?pong.c.width:pong.c.height;
      pong.paddleHeight=length;
      pong.userY=clamp(pong.userY+(old-length)/2,0,axis-length);
      pong.aiY=clamp(pong.aiY+(old-length)/2,0,axis-length);
      if(typeof refreshPongCourtBounds==="function")refreshPongCourtBounds();
    }
    pong.palette.user=paddleColor();
  }
  const asset = (direction,name) => ROOT+"ping_ping_arrow_"+direction+"_"+name+".webp";
  const engineAsset=ROOT+"train_engine.webp";
  const wagonAssets=[1,2,3,4].map(n=>ROOT+"train_wagon"+n+".webp");
  const smokeAsset=ROOT+"train_smoke.webp";
  // Arithmetic is independent from Math practice difficulty and AI strength.
  const ranges={
    addition:[[1,5],[3,7],[4,10],[6,15],[10,20],[12,30],[20,45],[30,60],[40,80],[50,99],[80,149],[100,299]],
    multiply:[[1,3],[2,4],[2,5],[3,6],[3,8],[4,9],[5,12],[7,15],[11,19],[15,24],[21,39],[30,69]],
    divide:[[1,3],[2,4],[2,5],[3,6],[3,8],[4,9],[5,12],[7,15],[9,18],[11,24],[12,29],[14,39]]
  };
  function makeQuestion(operation,level,example=false){
    operation=OPS.includes(operation)?operation:"addition";level=safeLevel(level);
    const span=(ranges[operation]||ranges.addition)[level-1];
    let a=example?span[1]:int(span[0],span[1]);
    let b=example?span[1]:int(span[0],span[1]);
    if(operation==="multiply" && level>=10) b=example?14:int(11,24);
    if(operation==="divide" && level>=7) b=example?9:int(6,18);
    let answer,symbol;
    if(operation==="addition"){answer=a+b;symbol="+";}
    else if(operation==="subtraction"){a=a+b;answer=a-b;symbol="−";}
    else if(operation==="multiply"){answer=a*b;symbol="×";}
    else{a=a*b;answer=a/b;symbol="÷";}
    if(example && operation==="multiply" && level===12){a=41;b=14;answer=574;}
    const choices=new Set([answer]);
    const candidates=shuffle([answer-1,answer+1,answer-10,answer+10,answer-2,answer+2,Math.abs(a-b),a+b]);
    for(const candidate of candidates){if(candidate>=0 && Number.isInteger(candidate)) choices.add(candidate);if(choices.size===4)break;}
    for(let d=1;choices.size<4;d++) choices.add(answer+d);
    return {operation,level,a,b,answer,text:`${a} ${symbol} ${b}`,choices:shuffle([...choices])};
  }
  let introSeen=false, dialog=null, dialogWasRunning=false, restoreFocus=null;
  let guideObserver=null, guideScrollHandler=null;
  let pauseStarted=0, modalPaused=false, hiddenPaused=document.hidden, nativePaused=false;
  let heldPointers=new Map(),heldKeys=new Set(),releaseFrames=0;
  let train=null,trainSequence=0,activeTime=0,nextTrainAt=5,gameTimeScale=1,worldSlowdown=0;
  let mountedGame=null,lastSkin=null,toastTimer=0;
  const TRAIN_RETURN_SECONDS=15, TRAIN_FEEDBACK_SECONDS=0.95;
  const paused=()=>modalPaused||hiddenPaused||nativePaused;
  function releaseInput(){heldPointers.clear();heldKeys.clear();releaseFrames=0;document.querySelectorAll('.pong-arrow.is-held').forEach(e=>e.classList.remove('is-held'));}
  function updatePause(change){
    const was=paused();change();const now=performance.now();
    if(!was&&paused()){pauseStarted=now;releaseInput();window.MinikAudio?.stopAll();}
    if(was&&!paused()&&typeof pong!=="undefined"&&pong){
      const delay=now-pauseStarted;
      if(Number.isFinite(pong.simulationNow))pong.simulationNow+=delay;
      for(const key of ["startCountdownUntil","pointPauseStartedAt","pointPauseUntil","madnessActivatedAt","nextBalloonSpawnAt","nextMiscSpawnAt","ballChaosUntil","rallyStartedAt"]){if(pong[key])pong[key]+=delay;}
      for(const item of pong.madnessObjects||[]){if(item.spawnedAt)item.spawnedAt+=delay;if(item.hitCooldownUntil)item.hitCooldownUntil+=delay;}
      pong.lastFrameAt=now;pauseStarted=0;
    }
  }
  function controlHelp(){if(androidApp())return tr("touchArrowsHelp");return tr(control()==="arrows"?(mobile()?"touchArrowsHelp":"arrowsHelp"):control()+"Help");}
  function setControl(mode){
    if(androidApp())return; // Both touch controls are always available in the app.
    const allowed=mobile()?["arrows","swipe"]:["arrows","keyboard","mouse"];
    if(!allowed.includes(mode)) return;
    state[mobile()?"controlTouch":"controlDesktop"]=mode;releaseInput();save();
    if(typeof pong!=="undefined" && pong){ prepareLayout(pong.pcVertical); if(typeof resizePongForViewport==="function")resizePongForViewport(); }
    refreshControls();
    const help=document.querySelector('.scorebox.help');if(help) help.textContent=pongHelpText();
    const hint=document.getElementById('extrasControlHint');if(hint)hint.textContent=controlHelp();
  }
  function updateStorageNote(){
    const note=document.getElementById('pongStorageNote');
    if(note){note.textContent=storageAvailable?"":tr("storageWarning");note.hidden=storageAvailable;note.classList.toggle('storage-warning',!storageAvailable);}
  }
  function showToast(text){
    const toast=document.getElementById('pongExtraToast');if(!toast)return;
    toast.textContent=text;toast.hidden=false;clearTimeout(toastTimer);
    toastTimer=setTimeout(()=>{toast.hidden=true;},2100);
  }
  function updateTotals(){
    document.querySelectorAll('[data-total-points]').forEach(el=>el.textContent=String(state.points));
    const next=SKINS.find(s=>s.at>state.points);
    const progress=document.getElementById('skinProgress');
    if(progress){progress.max=next?next.at:1200;progress.value=Math.min(state.points,progress.max);}
    refreshControls();
  }
  function addPoints(amount=1){
    if(!Number.isSafeInteger(amount)||amount<=0)return;
    const before=skinFor(state.points).name;
    state.points+=Math.min(amount,Number.MAX_SAFE_INTEGER-state.points);
    save();updateTotals();
    if(skinFor(state.points).name!==before) showToast(tr("unlocked"));
  }
  function addPoint(){addPoints(1);}
  function prepareLayout(vertical){
    // Arrows have their own edge lanes. They cannot cover a paddle at its extremes.
    document.body.classList.toggle("pong-controls-arrows",control()==="arrows");
    document.body.classList.toggle("pong-controls-vertical",!!vertical);
  }
  function setTrainMode(mode){
    if(!["tap","off"].includes(mode))return;
    if(mode!==state.trainMode){
      train?.el.remove();train=null;
      state.trainMode=mode;nextTrainAt=activeTime+5;
    }
    save();
    const hint=document.getElementById("extrasTrainHint");
    if(hint)hint.textContent=tr(mode+"Help");
    const fields=document.getElementById("extrasTrainFields");
    if(fields){fields.disabled=mode==="off";fields.classList.toggle("train-disabled",mode==="off");}
  }
  function totalMarkup(){
    return `<span class="pong-total" dir="ltr" title="${tr('total')}" aria-label="${tr('total')}"><small dir="${lang === 'he' ? 'rtl' : 'ltr'}">${tr('totalShort')}:</small><span class="pong-total-number" dir="ltr"><b data-total-points>${state.points}</b></span></span><button type="button" class="pong-help-button" aria-label="${tr('settings')}" title="${tr('settings')}"><span class="pong-help-label">${tr('settings')}</span></button>`;
  }
  function refreshControls(){
    syncPaddleRank();
    const layer=document.getElementById('pongExtraControls');if(!layer)return;
    const vertical=!!pong.pcVertical;
    prepareLayout(vertical);
    layer.classList.toggle('paddle-sideways',!vertical);
    const name=skinFor(state.points).name;
    layer.querySelectorAll('.pong-arrow').forEach((btn,i)=>{
      btn.hidden=control()!=="arrows";
      const direction=i===0?"left":"right";
      if(name!==lastSkin||!btn.querySelector('img').getAttribute('src'))btn.querySelector('img').src=asset(direction,name);
      const label=vertical?(i===0?"←":"→"):(i===0?"↑":"↓");
      btn.setAttribute('aria-label', (typeof lang!=="undefined"&&lang==="he"?"הזזת המחבט ":"Move paddle ")+label);
    });
    lastSkin=name;
  }
  function bindArrow(button,sign){
    let pressedAt=0;
    button.addEventListener('pointerdown',event=>{
      if(event.button!==0||paused()||control()!=="arrows")return;
      event.preventDefault();button.setPointerCapture(event.pointerId);
      heldPointers.set(event.pointerId,sign);pressedAt=performance.now();button.classList.add('is-held');
    });
    const release=event=>{heldPointers.delete(event.pointerId);button.classList.remove('is-held');};
    button.addEventListener('pointerup',release);button.addEventListener('pointercancel',release);button.addEventListener('lostpointercapture',release);
    // Keyboard/assistive button activation performs a small useful step too.
    button.addEventListener('click',event=>{if(!paused() && (event.detail===0||performance.now()-pressedAt<130)){releaseFrames=sign*4;}});
    button.addEventListener('contextmenu',event=>event.preventDefault());
  }
  function mount(){
    if(typeof pong==='undefined'||!pong)return;
    releaseInput();mountedGame=pong;train=null;activeTime=0;nextTrainAt=5;lastSkin=null;worldSlowdown=0;gameTimeScale=1;
    const card=pong.c.closest('.canvas-card');
    const field=card.querySelector(".pong-playfield") || card;
    // Android's arrow gutters belong to the game surface too. Mount the train
    // outside the narrower ball court so neither gutter clips engines or wagons.
    const fullWidthTrain=androidApp()&&typeof isPongMobileLandscape==="function"&&isPongMobileLandscape();
    (fullWidthTrain?card:field).insertAdjacentHTML("beforeend",`<div id="pongTrainLayer" class="pong-train-layer${fullWidthTrain?' pong-train-fullwidth':''}" aria-label="${tr("trainLabel")}"></div>`);
    (document.getElementById("pongControlDock") || card).insertAdjacentHTML('beforeend',`
      <div id="pongExtraControls" class="pong-extra-controls">
        <button type="button" class="pong-arrow pong-arrow-negative"><img alt="" draggable="false"></button>
        <button type="button" class="pong-arrow pong-arrow-positive"><img alt="" draggable="false"></button>

      </div>
      <div id="pongExtraToast" class="pong-extra-toast" role="status" aria-live="polite" hidden></div>`);
    document.querySelectorAll('#pongExtraControls .pong-arrow').forEach((b,i)=>bindArrow(b,i===0?-1:1));
    document.querySelectorAll(".pong-header-center,.pong-landscape-center").forEach(toolbar=>{
      toolbar.insertAdjacentHTML("beforeend",totalMarkup());
      toolbar.querySelector(".pong-help-button").addEventListener("click",()=>openSettings(false));
    });
    if(typeof resizePongForViewport==="function")resizePongForViewport();
    const setup=document.querySelector('.pong-setup-actions');
    if(setup){const help=document.createElement('button');help.type='button';help.className='pong-setup-help';help.innerHTML=`<span class="pong-setup-help-label">${tr('settings')}</span>`;help.setAttribute('aria-label',tr('settings'));help.addEventListener('click',()=>openSettings(false));setup.appendChild(help);}
    // Restore every score display, including the compact in-field HUD, before the first point.
    updateTotals();
    if(!androidApp()&&!introSeen){introSeen=true;openSettings(true);}
  }
  const guideCopy = () => lang === 'he' ? {
    how:'איך משחקים', settings:'הגדרות', more:'עוד בהמשך', start:'התחלת משחק',
    resume:'חזרה למשחק', result:'חזרה לתוצאה', setup:'חזרה להכנה',
    objects:'טירוף הבלונים', objectMode:'האובייקטים מופיעים כאשר טירוף הבלונים פעיל.',
    balloon:'בלון מתפוצץ ומשנה את זווית הכדור. מקבלים נקודה למצטבר רק אם המחבט שלכם היה האחרון שנגע בכדור — ולא המחבט של מיניק.',
    balls:'כדור הים וכדור צמר הגפן משנים את כיוון כדור המשחק בפגיעה. הם אינם מתפוצצים.',
    cloud:'ענן מאט או מאיץ את הכדור בלי לשנות את כיוונו.',
    car:'המכונית משנה את כיוון הכדור וממשיכה בנסיעה.',
    train:'לוחצים על הקרון הנכון כדי לקבל 3 נקודות למצטבר. רק לחיצה עונה. בטירוף הבלונים הכדור קופץ מהרכבת; כשהאפשרות כבויה, הוא עובר דרכה. בהגדרות אפשר לשחק בלי רכבת.',
    trainMore:'הרכבת חוזרת 15 שניות אחרי שיצאה. תשובה נכונה מקשה את השאלה הבאה; טעות מקלה עליה. הרמה נשמרת לפעם הבאה.',
    control:androidApp()?'החזיקו חץ או החליקו את האצבע ימינה ושמאלה על המחבט כדי להזיז אותו. שתי האפשרויות זמינות תמיד.':'החזיקו חץ או החליקו את האצבע ימינה ושמאלה על המחבט כדי להזיז אותו. במחשב אפשר גם להשתמש במקלדת.'
  } : {
    how:'How to play', settings:'Settings', more:'More below', start:'Start game',
    resume:'Resume game', result:'Back to results', setup:'Back to setup',
    objects:'Balloon Madness', objectMode:'These objects appear when Balloon Madness is on.',
    balloon:'A balloon pops and changes the ball’s angle. It adds 1 total point only if your paddle was the last one to touch the ball — not Minik’s.',
    balls:'The beach ball and cotton-candy ball change the direction of the game ball when hit. They do not pop.',
    cloud:'A cloud slows down or speeds up the ball without changing its direction.',
    car:'The car changes the ball’s direction and keeps driving.',
    train:'Tap the correct wagon for 3 total points. Only a tap answers. With Balloon Madness on, the ball rebounds from the train; with it off, the ball passes through. In Settings you can turn the train off.',
    trainMore:'The next train arrives 15 seconds after the last one leaves. Correct answers make the next question harder; mistakes make it easier. Your level is saved.',
    control:androidApp()?'Hold an arrow or slide your finger left and right on the paddle to move it. Both are always available.':'Hold an arrow or slide your finger left and right on the paddle to move it. On a computer, the keyboard arrows also work.'
  };
  function openSettings(first=false){
    if(dialog||typeof pong==='undefined'||!pong||view!=="pong")return;
    restoreFocus=document.activeElement;dialogWasRunning=!pong.waitingForStart&&!pong.over;
    updatePause(()=>{modalPaused=true;});
    document.getElementById('pongOrientationHint')?.remove();
    const gc=guideCopy(), currentSkin=skinFor(state.points);
    const modes=mobile()?["arrows","swipe"]:["arrows","keyboard","mouse"];
    const action=tr("close");
    dialog=document.createElement('div');dialog.className='pong-guide-overlay';dialog.id='pongGuideOverlay';
    dialog.innerHTML=`<section class="pong-guide" role="dialog" aria-modal="true" aria-labelledby="pongGuideTitle" dir="${lang==='he'?'rtl':'ltr'}">
      <header class="pong-guide-heading"><img src="assets/minik-brand.png" alt=""><div><h2 id="pongGuideTitle">${tr('settings')}</h2><p>${tr('intro')}</p></div><button type="button" class="pong-guide-close" aria-label="${tr('close')}"><img class="app-back-art" src="assets/arrow_back.webp" alt=""></button></header>
      <div class="pong-guide-tabs" role="tablist" aria-label="${tr('settings')}">
        <button id="guideTabHow" role="tab" aria-selected="true" aria-controls="guideHow" tabindex="0" data-guide-tab="how">${gc.how}</button>
        <button id="guideTabSettings" role="tab" aria-selected="false" aria-controls="guideSettings" tabindex="-1" data-guide-tab="settings">${gc.settings}</button>
      </div>
      <div id="guideHow" class="pong-guide-scroll" role="tabpanel" aria-labelledby="guideTabHow" tabindex="0">
        <div class="pong-guide-how-columns">
          <section class="pong-guide-card"><h3>${tr('controls')}</h3><p>${gc.control}</p><h3 class="guide-subtitle">${tr('train')}</h3><img class="guide-engine" src="${engineAsset}" alt=""><p>${gc.train}</p><p>${gc.trainMore}</p></section>
          <section class="pong-guide-card skin-collection"><h3>${tr('skins')}</h3><div class="extras-points"><span><strong data-total-points>${state.points}</strong> ${tr('total')}</span><progress id="skinProgress" max="${SKINS.find(s=>s.at>state.points)?.at||1200}" value="${Math.min(state.points,1200)}"></progress></div>
          <div class="pong-skin-grid">${SKINS.map(s=>`<article class="pong-skin ${s.name===currentSkin.name?'skin-current':''} ${state.points<s.at?'skin-locked':''}"><div class="skin-pair" dir="ltr"><img src="${asset('left',s.name)}" alt=""><img src="${asset('right',s.name)}" alt=""></div><strong>${tr(s.name)}</strong><span>${s.at} ${tr('points')}</span><small>${s.name===currentSkin.name?tr('current'):state.points>=s.at?tr('available'):`${tr('toGo')} ${s.at-state.points}`}</small></article>`).join('')}</div><p>${tr('arrowRandom')}</p><p>${tr('scoring')}</p><p id="pongStorageNote" class="extras-muted"></p></section>
        </div>
        <section class="pong-guide-card pong-object-guide"><h3>${gc.objects}</h3><p class="extras-muted">${gc.objectMode}</p>
          <div class="pong-object-row"><div class="object-pictures"><img src="assets/balloon1.webp" alt=""></div><p>${gc.balloon}</p></div>
          <div class="pong-object-row"><div class="object-pictures"><img src="assets/s05_beach_ball_round.webp" alt=""><img src="assets/cotton_candy_ball.webp" alt=""></div><p>${gc.balls}</p></div>
          <div class="pong-object-row"><div class="object-pictures"><img src="assets/cloud_blue_a.webp" alt=""></div><p>${gc.cloud}</p></div>
          <div class="pong-object-row"><div class="object-pictures"><img src="assets/minik_rainbow_car.webp" alt=""></div><p>${gc.car}</p></div>
        </section>
      </div>
      <div id="guideSettings" class="pong-guide-scroll" role="tabpanel" aria-labelledby="guideTabSettings" tabindex="0" hidden>
        <div class="pong-guide-columns">
          <div class="pong-guide-settings">
            ${androidApp()?"":`<section class="pong-guide-card"><label class="extras-label" for="extrasControl">${tr('controls')}</label><select id="extrasControl">${modes.map(m=>`<option value="${m}" ${m===control()?'selected':''}>${tr(m)}</option>`).join('')}</select><p id="extrasControlHint">${controlHelp()}</p><p class="extras-muted">${tr('axisHelp')}</p></section>`}
            <section class="pong-guide-card extras-match"><h3>${tr('match')}</h3>
              <label for="extrasAI">${tr('ai')}</label><select id="extrasAI">${['beginner','medium','hard'].map(d=>`<option value="${d}" ${pongDifficulty===d?'selected':''}>${t(d)}</option>`).join('')}</select>
              <label for="extrasTarget">${tr('target')}:</label><select id="extrasTarget">${[3,5,7,11].map(n=>`<option value="${n}" ${pongTargetScore===n?'selected':''}>${n}</option>`).join('')}</select>
              <label for="extrasMadness">${tr('madness')}:</label><select id="extrasMadness"><option value="true" ${pongBalloonMadness?'selected':''}>${tr('yes')}</option><option value="false" ${!pongBalloonMadness?'selected':''}>${tr('no')}</option></select>
            </section>
          </div>
          <section class="pong-guide-card train-settings"><h3>${tr('train')}</h3><p>${tr('trainHelp')}</p>
            <label class="extras-label" for="extrasTrainMode">${tr('trainMode')}</label><select id="extrasTrainMode">${['tap','off'].map(m=>`<option value="${m}" ${m===state.trainMode?'selected':''}>${tr(m+'Mode')}</option>`).join('')}</select><p id="extrasTrainHint">${tr(state.trainMode+'Help')}</p>
            <fieldset id="extrasTrainFields" ${state.trainMode==='off'?'disabled class="train-disabled"':''}>
            <label class="extras-label" for="extrasOperation">${tr('operation')}</label><select id="extrasOperation">${OPS.map(op=>`<option value="${op}" ${op===state.operation?'selected':''}>${tr(op)}</option>`).join('')}</select>
            <label class="extras-label train-level-label" for="extrasLevel">${tr('difficulty')} <output id="extrasLevelValue">${state.levels[state.operation]} / 12</output></label>
            <input id="extrasLevel" type="range" min="1" max="12" step="1" value="${state.levels[state.operation]}" dir="ltr">
            <div class="train-example"><span>${tr('example')}</span><strong id="extrasExample" dir="ltr">${makeQuestion(state.operation,state.levels[state.operation],true).text} = ?</strong></div><p class="extras-muted">${tr('adaptive')}</p></fieldset>
          </section>
        </div>
      </div>
      <button type="button" class="pong-guide-more" aria-label="${gc.more}" hidden><span>${gc.more}</span><span aria-hidden="true">↓</span></button>
      <footer class="pong-guide-footer"><button type="button" class="primary pong-guide-continue">${action}</button></footer>
    </section>`;
    // On Android landscape, keep navigation in the highest row instead of
    // spending a second full row on tabs above the already-short content area.
    if(document.documentElement.classList.contains('minik-android-inset-host')) {
      dialog.querySelector('.pong-guide-heading').appendChild(dialog.querySelector('.pong-guide-tabs'));
    }
    document.body.appendChild(dialog);document.body.classList.add('pong-guide-open');updateStorageNote();
    let activeTab='how';
    const activePanel=()=>dialog?.querySelector(activeTab==='how'?'#guideHow':'#guideSettings');
    const updateScrollCue=()=>{
      if(!dialog)return;
      const panel=activePanel(), cue=dialog.querySelector('.pong-guide-more');
      const overflow=panel.scrollHeight>panel.clientHeight+4;
      const more=panel.scrollHeight-panel.clientHeight-panel.scrollTop>6;
      // Reserve the cue's row while a panel can scroll; avoid resize/hide oscillation.
      cue.hidden=!overflow;cue.disabled=!more;cue.style.visibility=more?'visible':'hidden';
    };
    function selectTab(tab,focus=false){
      activeTab=tab;
      dialog.querySelectorAll('[data-guide-tab]').forEach(btn=>{
        const selected=btn.dataset.guideTab===tab;
        btn.setAttribute('aria-selected',String(selected));btn.tabIndex=selected?0:-1;
        dialog.querySelector('#'+btn.getAttribute('aria-controls')).hidden=!selected;
        if(selected&&focus)btn.focus();
      });
      requestAnimationFrame(updateScrollCue);
    }
    dialog.querySelectorAll('[data-guide-tab]').forEach(btn=>{
      btn.addEventListener('click',()=>selectTab(btn.dataset.guideTab));
      btn.addEventListener('keydown',event=>{
        if(['ArrowLeft','ArrowRight','Home','End'].includes(event.key)){
          event.preventDefault();selectTab(event.key==='Home'?'how':event.key==='End'?'settings':activeTab==='how'?'settings':'how',true);
        }
      });
    });
    dialog.querySelectorAll('.pong-guide-scroll').forEach(panel=>panel.addEventListener('scroll',updateScrollCue,{passive:true}));
    dialog.querySelector('.pong-guide-more').addEventListener('click',()=>{
      const panel=activePanel();panel.scrollBy({top:Math.max(80,panel.clientHeight*.72),behavior:matchMedia('(prefers-reduced-motion:reduce)').matches?'auto':'smooth'});
    });
    guideObserver=new ResizeObserver(updateScrollCue);
    dialog.querySelectorAll('.pong-guide-scroll').forEach(panel=>guideObserver.observe(panel));
    requestAnimationFrame(updateScrollCue);
    dialog.querySelector('.pong-guide-continue').addEventListener('click',()=>closeSettings(false));
    dialog.querySelector('.pong-guide-close').addEventListener('click',()=>closeSettings(false));
    dialog.querySelector('#extrasControl')?.addEventListener('change',ev=>setControl(ev.target.value));
    dialog.querySelector('#extrasTrainMode').addEventListener('change',ev=>setTrainMode(ev.target.value));
    const level=dialog.querySelector('#extrasLevel');
    const refreshExample=()=>{
      level.value=String(state.levels[state.operation]);
      dialog.querySelector('#extrasLevelValue').textContent=`${level.value} / 12`;
      dialog.querySelector('#extrasExample').textContent=makeQuestion(state.operation,+level.value,true).text+' = ?';
    };
    dialog.querySelector('#extrasOperation').addEventListener('change',ev=>{
      if(!OPS.includes(ev.target.value))return;state.operation=ev.target.value;save();refreshExample();
    });
    level.addEventListener('input',()=>{state.levels[state.operation]=safeLevel(+level.value);refreshExample();});
    level.addEventListener('change',save);
    dialog.querySelector('#extrasAI').addEventListener('change',ev=>setPongDifficulty(ev.target.value));
    dialog.querySelector('#extrasTarget').addEventListener('change',ev=>setPongTargetScore(+ev.target.value));
    dialog.querySelector('#extrasMadness').addEventListener('change',ev=>setBalloonMadness(ev.target.value==='true'));
    dialog.querySelector('.pong-guide-close').focus({preventScroll:true});
  }
  function closeSettings(play){
    if(!dialog)return;
    save();guideObserver?.disconnect();guideObserver=null;dialog.remove();dialog=null;document.body.classList.remove('pong-guide-open');
    updatePause(()=>{modalPaused=false;});
    if(play && pong && (pong.waitingForStart||pong.over)){
      // New game uses the same complete 3, 2, 1 countdown as the setup button.
      pongMobileStartRequested=true;pongLandscapeCountdownRequested=true;renderPong();
    } else if(play && pong && !dialogWasRunning){pong.waitingForStart=false;}
    const focus=restoreFocus?.isConnected?restoreFocus:document.querySelector('.pong-help-button');
    focus?.focus({preventScroll:true});
  }
  function createTrain(){
    if(!pong||pong.over||pong.waitingForStart||state.trainMode==="off")return;
    const layer=document.getElementById('pongTrainLayer');if(!layer)return;
    const question=makeQuestion(state.operation,state.levels[state.operation]);
    const id=++trainSequence, direction=Math.random()<.5?-1:1;
    const el=document.createElement('div');el.className='question-train';el.dataset.direction=String(direction);
    el.dataset.answerMode=state.trainMode;
    const engine=document.createElement('div');engine.className='train-engine train-unit';
    engine.innerHTML=`<img class="train-sprite" src="${engineAsset}" alt=""><span class="train-label" dir="ltr">${question.text.length>8?question.text.replace(/ /g,""):question.text}</span><img class="train-smoke" src="${smokeAsset}" alt="">`;
    el.appendChild(engine);
    question.choices.forEach((answer,i)=>{
      // Only a short tap answers; a drag continues to
      // reach the court so moving the paddle still feels natural.
      const wagon=document.createElement('button');
      wagon.type='button';
      wagon.className='train-wagon train-unit';wagon.dataset.answer=String(answer);
      wagon.setAttribute('aria-label',`${tr('trainAnswer')} ${answer}`);
      wagon.innerHTML=`<img class="train-sprite" src="${wagonAssets[i]}" alt=""><span class="train-label" dir="ltr">${answer}</span>`;
      {
        const touches=new Map();
        wagon.addEventListener('pointerdown',e=>{
          e.stopPropagation();
          if(e.pointerType!=="mouse"){
            e.preventDefault();touches.set(e.pointerId,{x:e.clientX,y:e.clientY});
            wagon.setPointerCapture(e.pointerId);
          }
        });
        wagon.addEventListener('pointerup',e=>{
          const start=touches.get(e.pointerId);touches.delete(e.pointerId);
          if(start){e.preventDefault();e.stopPropagation();
            if(Math.hypot(e.clientX-start.x,e.clientY-start.y)<14)answerTrain(id,i,'tap');
          }
        });
        wagon.addEventListener('pointercancel',e=>touches.delete(e.pointerId));
        wagon.addEventListener('lostpointercapture',e=>touches.delete(e.pointerId));
        wagon.addEventListener('click',e=>{e.stopPropagation();answerTrain(id,i,'tap');});
      }
      el.appendChild(wagon);
    });
    layer.replaceChildren(el);
    train={id,question,el,direction,duration:8,progress:0,answered:false,hornPlayed:false,entered:false,slowdown:0,
      answerCount:0,feedbackUntil:0,contactLock:false,vertical:pong.pcVertical,rects:[],previousRects:[],hitRects:[],previousHitRects:[]};
    positionTrain(0);
  }
  function answerTrain(id,index,source){
    if(!train||train.id!==id||paused()||pong.over||pong.waitingForStart||pong.startCountdownUntil)return;
    if(source!=='tap'||train.answered)return;
    if(!Number.isInteger(index)||index<0||index>=train.question.choices.length)return;
    const q=train.question,correct=q.choices[index]===q.answer;
    // One accepted tap per train, after all duplicate/pause/answer guards.
    window.MinikAudio?.play(correct ? "success_in_a_raw_sound" : "failure_answer_sound", "pong-train");
    train.answerCount++;train.lastCorrect=correct;train.feedbackUntil=activeTime+TRAIN_FEEDBACK_SECONDS;
    train.answered=true;train.answeredAt=activeTime;
    // Each accepted answer counts. The current pass keeps its question; the next
    // generated question uses the updated, per-operation difficulty.
    state.levels[q.operation]=clamp(state.levels[q.operation]+(correct?1:-1),1,12);
    if(correct)addPoints(3);else save();
    const engine=train.el.querySelector('.train-engine');
    engine.classList.toggle('train-correct',correct);engine.classList.toggle('train-wrong',!correct);
    train.el.querySelectorAll('.train-wagon').forEach((wagon,i)=>{
      wagon.disabled=true;
      wagon.classList.toggle('train-correct',q.choices[i]===q.answer);
      wagon.classList.toggle('train-wrong',i===index&&!correct);
    });
    showToast(correct?tr('correct'):`${tr('incorrect')} ${q.answer}`);
  }
  function positionTrain(progress){
    if(!train||!train.el.isConnected)return;
    const c=pong.c,vertical=pong.pcVertical,axis=vertical?c.width:c.height;
    const touch=mobile();
    const readableUnit=Math.ceil((Math.max(...train.question.choices.map(n=>String(n).length))*7.4+8)/.84);
    const unit=touch?clamp(axis*.96/5.55,Math.max(76,readableUnit*2),Math.max(100,readableUnit*2)):clamp(axis*.68/5.55,38,94);
    const textNeed=train.question.text.length*7.2+12;
    const engineWidth=touch?Math.max(unit*1.45,textNeed):unit*1.55,gap=2;
    const length=engineWidth+4*unit+4*gap;
    train.length=length;
    const fullWidth=vertical&&train.el.parentElement?.classList.contains('pong-train-fullwidth');
    const geometryKey=[c.width,c.height,vertical,train.direction,!!fullWidth,window.innerWidth,window.innerHeight].join(":");
    const geometryChanged=train.geometryKey!==geometryKey;
    if(geometryChanged){
      train.surface={x:0,y:0,sx:1,sy:1,start:0,end:axis};
      if(fullWidth){
        const court=c.getBoundingClientRect(),surface=train.el.parentElement.getBoundingClientRect();
        if(court.width>0&&court.height>0){
          const sx=court.width/c.width,sy=court.height/c.height;
          train.surface={x:court.left-surface.left,y:court.top-surface.top,sx,sy,
            start:(surface.left-court.left)/sx,end:(surface.left+surface.width-court.left)/sx};
        }
      }
    }
    const surface=train.surface,span=surface.end-surface.start;
    // Keep the same travel speed, but enter/leave at the actual outer screen edge.
    train.duration=8*(span+length)/(axis+length);
    const along=surface.start+(train.direction>0?-length+progress*(span+length):span-progress*(span+length));
    train.along=along;
    // A clear corridor beyond the computer paddle, never the player/control lane.
    const across=vertical
      ? Math.min(Math.max(68,c.height*.20),Math.max(42,c.height-unit-48))
      : Math.max(34,c.width-unit-48);
    if(geometryChanged){
      train.geometryKey=geometryKey;
      train.el.classList.toggle('train-travels-down',!vertical);
      train.el.style.width=length+'px';train.el.style.height=unit+'px';
      train.el.style.flexDirection=train.direction>0?'row-reverse':'row';
      train.el.style.left='0';train.el.style.top='0';train.el.style.transformOrigin='0 0';
      train.el.querySelectorAll('.train-unit').forEach((item,i)=>{
        item.style.width=(i===0?engineWidth:unit)+'px';
        item.querySelector('.train-sprite').style.transform=train.direction>0?'scaleX(-1)':'none';
        const label=item.querySelector('.train-label');
        label.style.transform=vertical?'none':'rotate(-90deg)';
        label.style.fontSize=(touch?Math.max(15,Math.min(21,(i===0?engineWidth:unit)*.84/(label.textContent.length*.62))):Math.max(11,Math.min(18,unit*.25,(i===0?engineWidth:unit)*.82/(label.textContent.length*.63))))+'px';
      });
    }
    train.el.style.transform=vertical
      ? `translate3d(${surface.x+along*surface.sx}px,${surface.y+across*surface.sy}px,0) scale(${surface.sx},${surface.sy})`
      : `translate3d(${across+unit}px,${along}px,0) rotate(90deg)`;
    const rects=[],hitRects=[];
    const engineLeft=train.direction>0?length-engineWidth:0;
    hitRects.push(vertical?{x:along+engineLeft,y:across,w:engineWidth,h:unit,index:0,answerIndex:null}
      :{x:across,y:along+engineLeft,w:unit,h:engineWidth,index:0,answerIndex:null});
    for(let i=0;i<4;i++){
      const left=train.direction>0?length-engineWidth-gap-(i+1)*unit-i*gap:engineWidth+(i+1)*gap+i*unit;
      hitRects.push(vertical?{x:along+left,y:across,w:unit,h:unit,index:i+1,answerIndex:i}
        :{x:across,y:along+left,w:unit,h:unit,index:i+1,answerIndex:i});
      // Target is the wagon's body/writing panel, not the transparent sprite margins.
      const x=left+unit*.08,y=unit*.25,w=unit*.84,h=unit*.69;
      rects.push(vertical?{x:along+x,y:across+y,w,h,index:i}
        :{x:across+unit-y-h,y:along+x,w:h,h:w,index:i});
    }
    train.previousRects=geometryChanged?rects:train.rects;
    train.rects=rects;
    train.previousHitRects=geometryChanged?hitRects:train.hitRects;
    train.hitRects=hitRects;
  }
  function overlapsCircle(rect,x,y,r){
    const dx=x-clamp(x,rect.x,rect.x+rect.w),dy=y-clamp(y,rect.y,rect.y+rect.h);
    return dx*dx+dy*dy<=r*r;
  }
  function sweepCircleRect(previous,ball,rect,oldRect=rect){
    // Relative motion handles a wagon moving sideways as well as a fast ball.
    // Rounded corners avoid the false corner contacts of an expanded AABB.
    const sx=previous.x-oldRect.x,sy=previous.y-oldRect.y;
    const dx=ball.x-rect.x-sx,dy=ball.y-rect.y-sy,r=ball.r,w=rect.w,h=rect.h;
    if(overlapsCircle({x:0,y:0,w,h},sx,sy,r))return 0;
    const hits=[];
    if(dx!==0){for(const x of [-r,w+r]){const t=(x-sx)/dx,y=sy+t*dy;if(t>=0&&t<=1&&y>=0&&y<=h)hits.push(t);}}
    if(dy!==0){for(const y of [-r,h+r]){const t=(y-sy)/dy,x=sx+t*dx;if(t>=0&&t<=1&&x>=0&&x<=w)hits.push(t);}}
    const a=dx*dx+dy*dy;
    if(a>1e-12){
      for(const [cx,cy] of [[0,0],[w,0],[0,h],[w,h]]){
        const ox=sx-cx,oy=sy-cy,b=2*(ox*dx+oy*dy),disc=b*b-4*a*(ox*ox+oy*oy-r*r);
        if(disc<0)continue;
        const t=(-b-Math.sqrt(disc))/(2*a),x=sx+t*dx,y=sy+t*dy;
        if(t>=0&&t<=1&&(cx===0?x<=0:x>=w)&&(cy===0?y<=0:y>=h))hits.push(t);
      }
    }
    return hits.length?Math.min(...hits):null;
  }
  function reflectTowardPlayer(ball,vertical){
    const speed=Math.hypot(ball.vx,ball.vy);if(speed<=1e-12)return;
    const oldSide=vertical?ball.vx:ball.vy;
    const main=Math.max(Math.abs(vertical?ball.vy:ball.vx),speed*.12);
    const side=Math.sign(oldSide)*Math.sqrt(Math.max(0,speed*speed-main*main));
    // Mirror against the face toward the user; retain speed and lateral sign.
    if(vertical){ball.vx=side;ball.vy=main;}else{ball.vx=-main;ball.vy=side;}
  }
  function collideTrain(previous,now){
    if(!pongBalloonMadness||state.trainMode==="off"||!train||paused()||!pong||pong.over||pong.waitingForStart||pong.startCountdownUntil||pong.pointPauseUntil)return false;
    const ball=pong.ball;
    if(Math.hypot(ball.vx,ball.vy)<1e-8)return false;
    if(train.contactLock){
      // One sound per contact. Re-arm only after real separation.
      if(train.hitRects.some(r=>overlapsCircle(r,previous.x,previous.y,ball.r+2)))return false;
      train.contactLock=false;
    }
    function firstHit(rects,oldRects){
      let found=null;
      for(const rect of rects){
      if(rect.x+rect.w<0||rect.y+rect.h<0||rect.x>pong.c.width||rect.y>pong.c.height)continue;
      const old=oldRects[rect.index]||rect;
      const t=sweepCircleRect(previous,ball,rect,old);
      if(t!==null&&(!found||t<found.t))found={rect,t};
      }
      return found;
    }
    // Engine and every wagon rebound the ball; collisions never choose an answer.
    const hit=firstHit(train.hitRects,train.previousHitRects);
    if(!hit)return false;
    const {rect,t}=hit;
    const x=previous.x+(ball.x-previous.x)*t,y=previous.y+(ball.y-previous.y)*t;
    reflectTowardPlayer(ball,pong.pcVertical);
    // Resolve outside the player-facing surface, then finish the unconsumed step.
    if(pong.pcVertical){ball.x=x;ball.y=rect.y+rect.h+ball.r+.6;}
    else{ball.x=rect.x-ball.r-.6;ball.y=y;}
    ball.x+=ball.vx*(1-t);ball.y+=ball.vy*(1-t);
    train.contactLock=true;
    window.MinikAudio?.play("train_hit", "pong-object");
    return true;
  }
  function tick(now,dt){
    if(!pong||mountedGame!==pong||paused())return;
    refreshControls();
    if(pong.over||pong.waitingForStart){if(train){train.el.remove();train=null;}worldSlowdown=0;gameTimeScale=1;return;}
    if(pong.startCountdownUntil)return;
    if(train?.entered){
      // Freeze the world earlier in the arrival; restore its previous pace more
      // gradually after answering. The train keeps its own slow-motion clock.
      worldSlowdown=train.answered
        ? clamp(worldSlowdown-dt/3.2,0,1)
        : clamp((train.progress-.03)/.25,0,1);
      train.slowdown=worldSlowdown;
    } else worldSlowdown=clamp(worldSlowdown-dt/3.2,0,1);
    // Keep easing back even when the train exits during recovery.
    gameTimeScale=1-worldSlowdown*worldSlowdown*(3-2*worldSlowdown);
    const movementEnabled=!paused();
    if(movementEnabled){
      let dir=0;
      if(control()==='arrows'){for(const n of heldPointers.values())dir+=n;}
      if(!mobile()&&['arrows','keyboard'].includes(control())){
        if(heldKeys.has(pong.pcVertical?'ArrowLeft':'ArrowUp'))dir--;
        if(heldKeys.has(pong.pcVertical?'ArrowRight':'ArrowDown'))dir++;
      }
      if(releaseFrames){dir+=Math.sign(releaseFrames);releaseFrames-=Math.sign(releaseFrames);}
      dir=Math.sign(dir);
      const bounds=getPongCourtBounds();
      const pixelsPerSecond=Math.max(280,(bounds.max-bounds.min)*1.08)*paddleSpeedFactor();
      pong.userY=clampPongPaddle(pong.userY+dir*pixelsPerSecond*dt*gameTimeScale);
    }
    // Pause the train's own clock during the brief point animation, not the whole match.
    if(pong.pointPauseUntil)return;
    activeTime+=dt*gameTimeScale;
    if(state.trainMode==="off")return;
    if(!train && activeTime>=nextTrainAt)createTrain();
    if(train){
      if(!train.hornPlayed){
        if(train.along<train.surface.end&&train.along+train.length>train.surface.start){
          train.entered=true;
          train.hornPlayed=true;
          window.MinikAudio?.play("train_horn", "pong-train-entry");
        }
      }
      if(train.feedbackUntil && activeTime>=train.feedbackUntil && !train.answered){
        train.el.querySelectorAll('.train-unit').forEach(e=>e.classList.remove('train-correct','train-wrong'));
        train.feedbackUntil=0;
      }
      const eased=train.slowdown*train.slowdown*(3-2*train.slowdown);
      const trainPace=train.entered?1-.70*eased:1;
      train.progress+=dt*trainPace/train.duration;
      if(train.progress>=1){train.el.remove();train=null;nextTrainAt=activeTime+TRAIN_RETURN_SECONDS;}
      else positionTrain(train.progress);
    }
  }
  function timeScale(){return gameTimeScale;}

  function stop(){
    window.MinikAudio?.stopAll();
    releaseInput();train?.el.remove();train=null;worldSlowdown=0;gameTimeScale=1;
    if(dialog){guideObserver?.disconnect();guideObserver=null;dialog.remove();dialog=null;document.body.classList.remove('pong-guide-open');}
    modalPaused=false;clearTimeout(toastTimer);
    document.body.classList.remove("pong-controls-arrows","pong-controls-vertical");
  }
  document.addEventListener('keydown',e=>{
    if(dialog){
      if(e.key==='Escape'){e.preventDefault();closeSettings(false);return;}
      if(e.key==='Tab'){
        const nodes=[...dialog.querySelectorAll('button,select,input,summary,[tabindex="0"]')].filter(n=>!n.disabled&&n.getClientRects().length);
        if(!nodes.length)return;
        const first=nodes[0],last=nodes[nodes.length-1];
        if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus();}
        else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus();}
      }
      return;
    }
    if(typeof view==='undefined'||view!=='pong'||paused()||mobile()||!['arrows','keyboard'].includes(control()))return;
    if(e.target.closest('input,select,textarea,[contenteditable="true"]'))return;
    const axisKeys=pong.pcVertical?['ArrowLeft','ArrowRight']:['ArrowUp','ArrowDown'];
    if(axisKeys.includes(e.key)){e.preventDefault();heldKeys.add(e.key);}
  });
  document.addEventListener('keyup',e=>heldKeys.delete(e.key));
  window.addEventListener('blur',releaseInput);
  document.addEventListener('visibilitychange',()=>updatePause(()=>{hiddenPaused=document.hidden;}));
  window.addEventListener('pagehide',()=>{releaseInput();save();});
  // API is also used by deterministic QA for the pure arithmetic/progression rules.
  window.PongExtras=Object.freeze({mount,tick,stop,isPaused:paused,timeScale,controlHelp,awardPoint:addPoint,awardPoints:addPoints,
    nativePause:value=>updatePause(()=>{nativePaused=!!value;}),
    prepareLayout,setTrainMode,collideTrain,sweepCircleRect,reflectTowardPlayer,
    canUsePointer:type=>!paused()&&(type==='mouse'?control()==='mouse':control()==='swipe'||control()==='arrows'),
    openSettings,closeSettings,setControl,makeQuestion,skinFor,prepareRound,paddleRank,paddleLengthFactor,
    difficulty:()=>state.opponentDifficulty,setDifficulty,paddleColor,
    matchSettings:()=>({targetScore:state.targetScore,balloonMadness:state.balloonMadness}),setMatchSettings,
    snapshot:()=>JSON.parse(JSON.stringify({state,storageAvailable,control:control(),timeScale:gameTimeScale,train:train?{id:train.id,question:train.question,answered:train.answered,mode:state.trainMode,progress:train.progress,slowdown:train.slowdown,entered:train.entered,feedbackUntil:train.feedbackUntil,answerCount:train.answerCount,lastCorrect:train.lastCorrect,rects:train.rects,geometryKey:train.geometryKey,surface:train.surface,along:train.along,length:train.length,direction:train.direction}:null,activeTime,nextTrainAt}))
  });
})();
