// v37: capability marker supplied by the local Android host, never by the website.
if(/MinikNative\/Android/.test(navigator.userAgent) && /MinikNativeInsets\/1/.test(navigator.userAgent)){
  document.documentElement.classList.add("minik-android-inset-host");
}

const copy = {
  he: {
    footer:"לומדים דרך משחק",
    heroTitle:"ללמוד. לשחק. להצליח.",
    heroText:"תרגול חיבור, חיסור, כפל וחילוק קצר, צבעוני ומהנה — ובין לבין משחק פינג פונג של מיניק.",
    start:"מתחילים לתרגל",
    pong:"לשחק פינג פונג",
    addSubCard:"חיבור וחיסור",
    addSubText:"מתרגלים חיבור וחיסור ב־10 שאלות קצרות וברורות.",
    mathCard:"כפל וחילוק",
    mathText:"בוחרים מספר 1–9, מתרגלים 10 שאלות ומקבלים תוצאה ברורה.",
    pongCard:"פינג פונג עם מיניק",
    pongText:"פינג פונג מהיר וצבעוני — עם עכבר או אצבע.",
    choose:"איזה מספר נתרגל?",
    chooseSub:"בחרו מספר אחד. אצל מיניק מתרגלים עד 9.",
    back:"חזרה",
    learn:"טבלת התרגול",
    addition:"תרגול חיבור",
    subtraction:"תרגול חיסור",
    additionDesc:"10 שאלות חיבור",
    subtractionDesc:"10 שאלות חיסור",
    additionButton:"חיבור",
    subtractionButton:"חיסור",
    multiply:"תרגול כפל",
    divide:"תרגול חילוק",
    multiplyDesc:"10 שאלות כפל",
    multiplyButton:"כפל",
    divideButton:"חילוק",
    divideDesc:"10 שאלות חילוק",
    correct:"נכון",
    wrong:"טעויות",
    question:"שאלה",
    of:"מתוך",
    resultTitle:"כל הכבוד!",
    resultText:"עכשיו אפשר לתרגל שוב או לבחור מספר חדש.",
    again:"לתרגל שוב",
    chooseAnother:"לבחור מספר אחר",
    home:"לעמוד הראשי",
    pongTitle:"פינג פונג עם מיניק",
    setupTitle:"מיניק – מקפצים ולומדים",
    pongHelpMouse:"הזיזו את המחבט בעזרת העכבר.",
    pongHelpTouch:"הזיזו את המחבט בעזרת האצבע.",
    pongFirstTo:"הראשון שמגיע ל־{score} מנצח.",
    restart:"התחלה",
    you:"אתם",
    minik:"מיניק",
    win:"ניצחתם! 🏆",
    lose:"מיניק ניצח הפעם 😺",
    great:"מעולה!",
    oops:"אופס, נמשיך",
    next:"הבא",
    brand:"© מיניק",
    brandPlain:"מיניק",
    mainSite:"לאתר הראשי של מיניק",
    rights:"© 2026 Apps By Bros · כל הזכויות שמורות",
    difficulty:"הרמה של מיניק:",
    yes:"כן",
    no:"לא",
    exit:"יציאה",
    gameClosed:"המשחק הסתיים",
    closeBrowserHint:"כדי לצאת, סגרו את הלשונית בדפדפן.",
    closeAppHint:"כדי לצאת מהאפליקציה, חזרו למסך הבית של המכשיר.",
    playAgain:"לשחק שוב",
    landscapeRecommendation:"מומלץ לסובב את המכשיר לרוחב לחוויית משחק טובה יותר.",
    beginner:"מתחיל",
    medium:"בינוני",
    hard:"קשה",
    pongNew:"חדש",
    pongHeight:"גובה המשחק",
    pongTableSize:"גודל שולחן המשחק",
    pongSizeSmall:"קטן",
    pongSizeMedium:"בינוני",
    pongSizeLarge:"גדול",
    balloonMadness:"טירוף בלונים",
    pongMadnessTeaser:"נסו את טירוף הבלונים!",
    targetScore:"ניקוד לניצחון:",
    practiceLevel:"רמת תרגול",
    mathEasy:"קל",
    mathMedium:"בינוני",
    mathHard:"קשה",
    gameDirection:"כיוון המשחק",
    bottomTop:"מלמטה למעלה",
    sideToSide:"מצד לצד",
    rotateToPlay:"סובבו את המכשיר לרוחב כדי לשחק",
    rotateHint:"הפינג פונג בנייד משחקים לרוחב"
  },
  en: {
    footer:"Learning through play",
    heroTitle:"Learn. Play. Grow.",
    heroText:"Short, colorful addition, subtraction, multiplication and division practice — plus a playful Minik ping-pong game.",
    start:"Start practicing",
    pong:"Play Ping Pong",
    addSubCard:"Add & Subtract",
    addSubText:"Practice addition and subtraction with 10 short, clear questions.",
    mathCard:"Multiply & Divide",
    mathText:"Choose a number from 1–9, answer 10 questions, and get a clear score.",
    pongCard:"Minik Ping Pong",
    pongText:"A fast colorful ping-pong game — play with a mouse or your finger.",
    choose:"Which number shall we practice?",
    chooseSub:"Pick one table. Minik practices up to 9.",
    back:"Back",
    learn:"Learn the table",
    addition:"Practice addition",
    subtraction:"Practice subtraction",
    additionDesc:"10 addition questions",
    subtractionDesc:"10 subtraction questions",
    additionButton:"Add",
    subtractionButton:"Subtract",
    multiply:"Practice multiplication",
    divide:"Practice division",
    multiplyDesc:"10 multiplication questions",
    multiplyButton:"Multiply",
    divideButton:"Divide",
    divideDesc:"10 division questions",
    correct:"Correct",
    wrong:"Wrong",
    question:"Question",
    of:"of",
    resultTitle:"Great job!",
    resultText:"You can practice again or choose a new number.",
    again:"Practice again",
    chooseAnother:"Choose another number",
    home:"Home",
    pongTitle:"Minik Ping Pong",
    setupTitle:"Minik Bounce & Learn",
    pongHelpMouse:"Move your paddle with the mouse.",
    pongHelpTouch:"Move your paddle with your finger.",
    pongFirstTo:"First to {score} wins.",
    restart:"Start",
    you:"You",
    minik:"Minik",
    win:"You won! 🏆",
    lose:"Minik wins this time 😺",
    great:"Great!",
    oops:"Oops, keep going",
    next:"Next",
    brand:"© Minik",
    brandPlain:"Minik",
    mainSite:"Minik main site",
    rights:"© 2026 Apps By Bros · All rights reserved",
    difficulty:"Minik level:",
    yes:"Yes",
    no:"No",
    exit:"Exit",
    gameClosed:"Game closed",
    closeBrowserHint:"To leave, close this browser tab.",
    closeAppHint:"To leave the app, return to your device’s Home screen.",
    playAgain:"Play again",
    landscapeRecommendation:"For a better game experience, turn your device sideways.",
    beginner:"Beginner",
    medium:"Medium",
    hard:"Hard",
    pongNew:"New",
    pongHeight:"Game height",
    pongTableSize:"Game table size",
    pongSizeSmall:"Small",
    pongSizeMedium:"Medium",
    pongSizeLarge:"Large",
    balloonMadness:"Balloon Madness",
    pongMadnessTeaser:"Try Balloon Madness!",
    targetScore:"Score to win:",
    practiceLevel:"Practice level",
    mathEasy:"Easy",
    mathMedium:"Medium",
    mathHard:"Hard",
    gameDirection:"Game direction",
    bottomTop:"Bottom to top",
    sideToSide:"Side to side",
    rotateToPlay:"Rotate your device to landscape to play",
    rotateHint:"Mobile Ping Pong is played in landscape"
  }
};

const mascot = {
  logo: "assets/minik-brand.png",
  main: "assets/mascot-rainbow-cat.webp",
  success: "assets/minik-success.webp",
  love: "assets/minik-love.webp",
  pong: "assets/minik-pong.webp",
  noFrames: [
    "assets/minik-no-1.webp",
    "assets/minik-no-2.webp",
    "assets/minik-no-3.webp",
    "assets/minik-no-2.webp",
    "assets/minik-no-1.webp"
  ]
};

const preferredBrowserLanguage = (
  (Array.isArray(navigator.languages) && navigator.languages[0]) ||
  navigator.language ||
  "en"
).toLowerCase();

const startedInHebrew = (
  preferredBrowserLanguage === "he" ||
  preferredBrowserLanguage === "iw" ||
  preferredBrowserLanguage.startsWith("he-") ||
  preferredBrowserLanguage.startsWith("iw-")
);
// Native product context never depends on the Balloon Madness setting.
const cameFromMath = true;
let carriedPongLang = null;
try{
  if(cameFromMath && sessionStorage.getItem("minikPongFromMath") === "1"){
    carriedPongLang = sessionStorage.getItem("minikPongLang");
  }
  sessionStorage.removeItem("minikPongFromMath");
}catch(_){}
const requestedPongLang = new URLSearchParams(window.location.search).get("lang");
if(cameFromMath && (requestedPongLang === "en" || (startedInHebrew && requestedPongLang === "he"))){
  carriedPongLang = requestedPongLang;
}
let lang = (carriedPongLang === "he" || carriedPongLang === "en")
  ? carriedPongLang
  : (startedInHebrew ? "he" : "en");
let view = "home";
let selectedN = 6;
let mode = "addition";
let mathFamily = "addsub";
let mathDifficulty = "easy";
let qIndex = 0, good = 0, bad = 0, locked = false, current = null, firstWrong = false, wrongChoices = new Set();
let recentCorrectQuestionKeys = [];
let modePreset = false;
let quizBackTarget = "learn";
const app = document.getElementById("app");
const langBtn = document.getElementById("langBtn");
const homeBtn = document.getElementById("homeBtn");
const feedbackLayer = document.getElementById("feedbackLayer");
const brandLogo = document.getElementById("brandLogo");
const pongBrandParams = new URLSearchParams(window.location.search);
const useStandalonePongBrand = !cameFromMath;
if(brandLogo){
  brandLogo.src = useStandalonePongBrand
    ? "assets/minik-brand.png"
    : "assets/minik-brand.png";
  brandLogo.alt = useStandalonePongBrand ? "Minik Ping Pong logo" : "Minik Math logo";
}

const screenTitle = document.getElementById("screenTitle");
let lastRenderedView = null;

function t(k){ return copy[lang][k] || k; }
function familyForMode(m){
  return (m === "addition" || m === "subtraction") ? "addsub" : "muldiv";
}
function modeSymbol(m){
  return ({addition:"+",subtraction:"−",multiply:"×",divide:"÷"})[m] || "";
}
function modeButtonLabel(m){
  return ({addition:t("additionButton"),subtraction:t("subtractionButton"),multiply:t("multiplyButton"),divide:t("divideButton")})[m] || m;
}
function modeLongLabel(m){
  return ({addition:t("addition"),subtraction:t("subtraction"),multiply:t("multiply"),divide:t("divide")})[m] || m;
}
function modeLabelMarkup(m, useLong=false){
  const label = useLong ? modeLongLabel(m) : modeButtonLabel(m);
  return `<span class="mode-label-order"><span class="mode-label-text">${label}</span><span class="mode-label-symbol" dir="ltr">${modeSymbol(m)}</span></span>`;
}
function modeDescription(m){
  return ({addition:t("additionDesc"),subtraction:t("subtractionDesc"),multiply:t("multiplyDesc"),divide:t("divideDesc")})[m] || "";
}
function learnTableTitle(n){
  if(mathFamily === "addsub") return lang === "he" ? `טבלת החיבור למספר ${n}` : `Addition Table for ${n}`;
  return lang === "he" ? `טבלת הכפל למספר ${n}` : `${n} Times Table`;
}
function mathDifficultyLabel(level){
  return level === "easy" ? t("mathEasy") : level === "medium" ? t("mathMedium") : t("mathHard");
}
function mathDifficultyMarkup(compact=false){
  return `<div class="math-difficulty ${compact ? "compact" : ""}" aria-label="${t("practiceLevel")}">
    <span class="math-difficulty-label">${t("practiceLevel")}</span>
    <div class="math-difficulty-buttons">
      ${["easy","medium","hard"].map(level=>`<button type="button" data-math-level="${level}" onclick="setMathDifficulty('${level}')" class="${mathDifficulty===level ? "active" : ""}">${mathDifficultyLabel(level)}</button>`).join("")}
    </div>
  </div>`;
}
window.setMathDifficulty = level => {
  if(!["easy","medium","hard"].includes(level)) return;
  mathDifficulty = level;
  if(view === "learn" || view === "home" || view === "choose") render();
};
function mathPracticeValues(){
  if(mathFamily === "addsub") {
    if(mathDifficulty === "easy") return Array.from({length:10},(_,i)=>i+1);
    if(mathDifficulty === "medium") return [5,8,11,14,17,20,23,26,29,30];
    return [20,28,36,44,52,60,68,76,84,90];
  }
  if(mathDifficulty === "easy") return Array.from({length:10},(_,i)=>i+1);
  if(mathDifficulty === "medium") return Array.from({length:10},(_,i)=>i+3);
  return Array.from({length:10},(_,i)=>i+11);
}
function questionCandidateValues(){
  if(mathFamily === "addsub") {
    if(mathDifficulty === "easy") return Array.from({length:10},(_,i)=>i+1);
    if(mathDifficulty === "medium") return Array.from({length:26},(_,i)=>i+5);
    return Array.from({length:71},(_,i)=>i+20);
  }
  if(mathDifficulty === "easy") return Array.from({length:10},(_,i)=>i+1);
  if(mathDifficulty === "medium") return Array.from({length:10},(_,i)=>i+3);
  return Array.from({length:10},(_,i)=>i+11);
}
function questionKeyFor(k){
  return `${mode}:${selectedN}:${mathDifficulty}:${k}`;
}
function randomPracticeValue(){
  const candidates = questionCandidateValues();
  const blocked = new Set(recentCorrectQuestionKeys.slice(-4));
  const available = candidates.filter(k=>!blocked.has(questionKeyFor(k)));
  const pool = available.length ? available : candidates;
  return pool[Math.floor(Math.random()*pool.length)];
}
function learnRows(){
  return mathPracticeValues().map(k=>{
    if(mathFamily === "addsub") return `${selectedN} + ${k} = ${selectedN+k}`;
    return `${selectedN} × ${k} = ${selectedN*k}`;
  });
}
function modeCardMarkup(m, tone){
  return `<button class="mode-card ${tone}" onclick="startQuiz('${m}','learn')">
    <div><strong>${modeLabelMarkup(m,true)}</strong><span>${modeDescription(m)}</span></div>
    <img src="${mascot.love}" alt="">
  </button>`;
}
function pongHelpText(){
  const touch = (navigator.maxTouchPoints || 0) > 0 ||
    (window.matchMedia && window.matchMedia("(pointer: coarse)").matches);
  const inputText = window.PongExtras ? PongExtras.controlHelp() : (touch ? t("pongHelpTouch") : t("pongHelpMouse"));
  return `${inputText} ${t("pongFirstTo").replace("{score}", String(pongTargetScore))}`;
}
function isPongMobileDevice(){
  const touch = (navigator.maxTouchPoints || 0) > 0;
  const coarse = window.matchMedia && window.matchMedia("(pointer: coarse)").matches;
  return (touch && coarse) || (window.matchMedia && window.matchMedia("(max-width: 760px)").matches);
}
function pongViewportSize(){
  const vv = window.visualViewport;
  const width = Math.max(
    document.documentElement.clientWidth || 0,
    vv ? vv.width : 0,
    window.innerWidth || 0
  );
  const height = Math.max(
    document.documentElement.clientHeight || 0,
    vv ? vv.height : 0,
    window.innerHeight || 0
  );
  return { width, height };
}
function isPongMobileLandscape(){
  if(!isPongMobileDevice()) return false;
  // Layout follows the actual window, including split-screen/browser windows,
  // not merely the physical display sensor's orientation.
  const viewport = pongViewportSize();
  // Android 16 (target SDK 36) no longer locks landscape on tablets. Their portrait window is
  // large enough for the same full-screen court, which already plays bottom-to-top.
  if(Math.min(viewport.width, viewport.height) >= 600) return true;
  return viewport.width > viewport.height * 1.08;
}

let pongOrientationHintShown = false;
let pongOrientationHintTimer = null;
function isPongCompactLandscape(){
  const size = pongViewportSize();
  return isPongMobileLandscape() && size.height <= 500;
}
function syncPongCompactState(){
  const compact = view === "pong" && isPongCompactLandscape();
  const playing = compact && !!pong && !pong.over && !pong.waitingForStart;
  const before = document.body.classList.contains("pong-immersive-playing");
  document.body.classList.toggle("pong-compact-landscape", compact);
  document.body.classList.toggle("pong-immersive-playing", playing);
  if(before !== playing && pong) requestAnimationFrame(resizePongForViewport);
}
function syncPongLandscapeClass(){
  const active = view === "pong" && isPongMobileLandscape();
  // Desktop gets a viewport-bound arena; phones keep their existing layout.
  const desktop = view === "pong" && !isPongMobileDevice();
  document.documentElement.classList.toggle("pong-desktop-active", desktop);
  document.body.classList.toggle("pong-desktop-active", desktop);
  document.body.classList.toggle("pong-landscape-active", active);
  document.body.classList.remove("pong-portrait-blocked");
  if(active || view !== "pong") document.getElementById("pongOrientationHint")?.remove();
  if(typeof pong !== "undefined") syncPongCompactState();
  return active;
}
function maybeShowPongOrientationHint(){
  if(view !== "pong" || !isPongMobileDevice() || isPongMobileLandscape() || pongOrientationHintShown) return;
  pongOrientationHintShown = true;
  const hint = document.createElement("div");
  hint.id = "pongOrientationHint";
  hint.className = "pong-orientation-hint";
  hint.setAttribute("role", "status");
  hint.textContent = t("landscapeRecommendation");
  document.body.appendChild(hint);
  pongOrientationHintTimer = setTimeout(()=>hint.remove(), 4000);
}
function setLang(next){
  lang = next === "he" ? "he" : "en";
  document.documentElement.lang = lang === "he" ? "he" : "en";
  document.documentElement.dir = lang === "he" ? "rtl" : "ltr";
  langBtn.hidden = !startedInHebrew;
  langBtn.textContent = lang === "he" ? "EN" : "HE";
  document.getElementById("mainSiteLink").textContent = t("mainSite");
  document.getElementById("footerRights").textContent = t("rights");
  render();
}
langBtn.onclick = ()=>{
  if(!startedInHebrew) return;
  setLang(lang === "he" ? "en" : "he");
};
homeBtn.onclick = ()=>go("home");

function render(){
  const viewChanged = lastRenderedView !== view;
  document.body.dataset.view = view;
  document.documentElement.dataset.view = view;
  syncPongLandscapeClass();
  if(screenTitle){
    screenTitle.hidden = view !== "pong";
    screenTitle.textContent = view === "pong" ? t("pongTitle") : "";
  }

  if(view==="home") renderHome();
  else if(view==="choose") renderChoose();
  else if(view==="learn") renderLearn();
  else if(view==="quiz") renderQuiz();
  else if(view==="result") renderResult();
  else if(view==="pong") renderPong();
  else if(view==="closed") exitPong();

  lastRenderedView = view;

  // This is a single-page app: browser scroll position otherwise survives screen changes.
  // Reset only on mobile and only when the logical screen actually changes.
  if(viewChanged && window.matchMedia("(max-width: 760px)").matches){
    requestAnimationFrame(()=>requestAnimationFrame(()=>{
      window.scrollTo(0,0);
      document.documentElement.scrollTop = 0;
      document.body.scrollTop = 0;
    }));
  }
}
function backButton(target){
  // LTR: left-pointing back arrow. RTL/Hebrew: right-pointing back arrow.
  return `<button class="back-btn" aria-label="${t("back")}" onclick="go('${target}')"><img class="app-back-art" src="assets/arrow_back.webp" alt="" draggable="false"></button>`;
}
function stopPongSession(){
  window.PongExtras?.stop();
  if(pongRAF) cancelAnimationFrame(pongRAF);
  pongRAF = null;
  clearTimeout(pongResizeTimer);
  clearTimeout(pongOrientationHintTimer);
  document.getElementById("pongOrientationHint")?.remove();
  if(pong){
    pong.over = true;
    pong.waitingForStart = true;
    pong.ball.vx = 0;
    pong.ball.vy = 0;
    pong.madnessObjects = [];
  }
}
// Embedded Pong always returns to Math; it never exits the Android app.
window.exitPong = ()=>go("home");
window.reopenPong = ()=>{
  view = "pong";
  pongMobileStartRequested = false;
  pongLandscapeCountdownRequested = false;
  render();
};
window.go = (target)=>{
  if(target === "home"){
    stopPongSession();
    try{ sessionStorage.setItem("minikMathReturnLang", lang); }catch(_){}
    // Replace Pong in history so Android Back cannot reopen a stopped match.
    window.location.replace("../index.html");
    return;
  }
  view=target; render();
};

window.openPongPage = ()=>{
  try{
    sessionStorage.setItem("minikPongLang", lang);
    sessionStorage.setItem("minikPongFromMath", "1");
  }catch(_){}
  window.location.href = "index.html?madness=off";
};

function renderHome(){
  app.innerHTML = `
    <section class="hero">
      <div class="hero-copy">
        <h1>${t("heroTitle")}</h1>
        <p>${t("heroText")}</p>
        <div class="actions">
          <button class="primary" onclick="startGenericPractice()">${t("start")}</button>
          <button class="secondary" onclick="openPongPage()">${t("pong")}</button>
        </div>
      </div>
      <div class="hero-art"><img src="${mascot.main}" alt="Minik"></div>
    </section>

    <section class="practice-level-section">
      ${mathDifficultyMarkup(false)}
    </section>

    <section class="game-grid">
      <article class="game-card addsub">
        <div>
          <div class="menu-illustration">
            <span class="menu-badge">➕ ➖</span>
            <img src="${mascot.love}" alt="Minik addition and subtraction">
          </div>
          <h3>${t("addSubCard")}</h3>
          <p>${t("addSubText")}</p>
        </div>
        <div class="actions math-mode-actions">
          <button class="primary" onclick="chooseModeFromHome('addition')">${modeLabelMarkup("addition")}</button>
          <button class="secondary" onclick="chooseModeFromHome('subtraction')">${modeLabelMarkup("subtraction")}</button>
        </div>
      </article>

      <article class="game-card math">
        <div>
          <div class="menu-illustration">
            <span class="menu-badge">✖️ ➗</span>
            <img src="${mascot.love}" alt="Minik math">
          </div>
          <h3>${t("mathCard")}</h3>
          <p>${t("mathText")}</p>
        </div>
        <div class="actions math-mode-actions">
          <button class="primary" onclick="chooseModeFromHome('multiply')">${modeLabelMarkup("multiply")}</button>
          <button class="secondary" onclick="chooseModeFromHome('divide')">${modeLabelMarkup("divide")}</button>
        </div>
      </article>

      <article class="game-card pong">
        <div>
          <div class="menu-illustration">
            <span class="menu-badge">🏓</span>
            <img src="${mascot.pong}" alt="${t("pongTitle")}">
          </div>
          <h3>${t("pongCard")}</h3>
          <p>${t("pongText")}</p>
          <p class="pong-madness-teaser">🎈 ${t("pongMadnessTeaser")}</p>
        </div>
        <div class="actions pong-card-actions"><button class="primary" onclick="openPongPage()">${t("pong")}</button></div>
      </article>
    </section>`;
}

window.startGenericPractice = () => {
  mathFamily = "addsub";
  mode = "addition";
  modePreset = false;
  view = "choose";
  render();
};

window.chooseModeFromHome = selectedMode => {
  mode = selectedMode;
  mathFamily = familyForMode(selectedMode);
  modePreset = true;
  view = "choose";
  render();
};

function renderChoose(){
  app.innerHTML = `
    <section class="panel">
      <div class="back-row">${backButton("home")}${modePreset ? `<div class="mode-title-inline">${modeLabelMarkup(mode)}</div>` : ""}<span></span></div>
      ${mathDifficultyMarkup(true)}
      <div class="section-title"><h2>${t("choose")}</h2><p>${t("chooseSub")}</p></div>
      <div style="display:flex;justify-content:center;margin:0 0 18px">
        <img class="quiz-mascot" src="${mascot.love}" alt="">
      </div>
      <div class="number-grid">
        ${[1,2,3,4,5,6,7,8,9].map(n=>`<button class="number-card" onclick="chooseN(${n})">${n}</button>`).join("")}
      </div>
    </section>`;
}
window.chooseN = n => {
  selectedN = n;
  if(modePreset){
    startQuiz(mode, "choose");
  } else {
    view = "learn";
    render();
  }
};

function renderLearn(){
  const rows = learnRows();
  const tableTitle = learnTableTitle(selectedN);
  const modes = mathFamily === "addsub"
    ? [modeCardMarkup("addition","addition"), modeCardMarkup("subtraction","subtraction")]
    : [modeCardMarkup("multiply","multiply"), modeCardMarkup("divide","divide")];
  app.innerHTML = `
    <section class="panel">
      <div class="back-row learn-back-row">
        ${backButton("choose")}
        <span class="progress-chip learn-title-chip">${tableTitle}</span>
        <span class="learn-back-spacer" aria-hidden="true"></span>
      </div>
      ${mathDifficultyMarkup(true)}
      <div class="learn-layout">
        <div class="table-card">
          <h3>${tableTitle}</h3>
          <div class="table-list">${rows.map(r=>`<div class="table-row">${r}</div>`).join("")}</div>
        </div>
        <div class="mode-stack">${modes.join("")}</div>
      </div>
    </section>`;
}

window.startQuiz = (m, backTarget = "learn") => {
  mode=m;
  mathFamily=familyForMode(m);
  quizBackTarget=backTarget;
  qIndex=0;
  good=0;
  bad=0;
  locked=false;
  firstWrong=false;
  wrongChoices=new Set();
  recentCorrectQuestionKeys=[];
  current=makeQuestion();
  view="quiz";
  render();
};

function makeQuestion(){
  const k = randomPracticeValue();
  let correct;
  let text;
  if(mode === "addition"){
    correct = selectedN + k;
    text = `${selectedN} + ${k} = ?`;
  }else if(mode === "subtraction"){
    correct = k;
    text = `${selectedN + k} − ${selectedN} = ?`;
  }else if(mode === "multiply"){
    correct = selectedN * k;
    text = `${selectedN} × ${k} = ?`;
  }else{
    correct = k;
    text = `${selectedN * k} ÷ ${selectedN} = ?`;
  }

  const set = new Set([correct]);
  const scale = correct >= 50 ? 10 : correct >= 20 ? 5 : 2;
  const deltas=[-2*scale,-scale,-3,-2,-1,1,2,3,scale,2*scale];
  let guard=0;
  while(set.size<4 && guard<60){
    guard++;
    const d=deltas[Math.floor(Math.random()*deltas.length)];
    const candidate=Math.max(0,correct+d);
    set.add(candidate);
  }
  while(set.size<4) set.add(correct + set.size + 1);
  return {key:questionKeyFor(k), k, text, correct, answers:[...set].sort(()=>Math.random()-.5)};
}
function renderQuiz(){
  app.innerHTML = `
    <section class="panel quiz-panel">
      <div class="back-row">${backButton(quizBackTarget)}<div class="mode-title-inline quiz-mode-title-inline">${modeLabelMarkup(mode)}</div><span class="progress-chip">${t("question")} ${qIndex+1} ${t("of")} 10</span></div>
      <div class="quiz-top">
        <div class="counter good"><span>${t("correct")}</span><strong>${good}</strong></div>
        <span class="progress-chip">${qIndex}/10</span>
        <div class="counter bad"><span>${t("wrong")}</span><strong>${bad}</strong></div>
      </div>
      <img id="quizMascot" class="quiz-mascot" src="${mascot.love}" alt="">
      <div class="quiz-question"><span class="quiz-equation">${current.text}</span></div>
      <div class="answers">
        ${current.answers.map(a=>`<button class="answer" data-answer="${a}" onclick="answer(${a})">${a}</button>`).join("")}
      </div>
      <div class="next-wrap">
        <button id="nextBtn" class="next-btn" type="button" onclick="nextAfterWrong()" hidden>${t("next")}</button>
      </div>
    </section>`;
}
window.answer = a => {
  if(locked) return;

  const isCorrect = a === current.correct;
  const buttons=[...document.querySelectorAll(".answer")];
  const clicked = buttons.find(b => Number(b.dataset.answer) === a);

  if(!isCorrect){
    if(wrongChoices.has(a)) return;
    wrongChoices.add(a);

    if(!firstWrong){
      firstWrong = true;
      bad++;
    }

    if(clicked){
      clicked.classList.add("wrong");
      clicked.disabled = true;
    }

    const nextBtn = document.getElementById("nextBtn");
    if(nextBtn) nextBtn.hidden = false;

    animateFailureMascot();
    return;
  }

  locked = true;

  if(!firstWrong){
    good++;
    recentCorrectQuestionKeys.push(current.key);
    recentCorrectQuestionKeys = recentCorrectQuestionKeys.slice(-4);
  }

  buttons.forEach(b=>{
    b.disabled = true;
    const v = Number(b.dataset.answer);
    if(v === current.correct) b.classList.add("correct");
    else if(!wrongChoices.has(v)) b.classList.add("dimmed");
  });

  const nextBtn = document.getElementById("nextBtn");
  if(nextBtn) nextBtn.hidden = true;

  showFeedback("success");

  setTimeout(()=>advanceQuestion(), 1850);
};

window.nextAfterWrong = () => {
  if(locked || !firstWrong) return;
  locked = true;

  const buttons=[...document.querySelectorAll(".answer")];
  buttons.forEach(b=>{
    b.disabled = true;
    const v = Number(b.dataset.answer);
    if(v === current.correct) b.classList.add("correct");
    else if(!wrongChoices.has(v)) b.classList.add("dimmed");
  });

  const nextBtn = document.getElementById("nextBtn");
  if(nextBtn) nextBtn.hidden = true;

  setTimeout(()=>advanceQuestion(), 900);
};

function advanceQuestion(){
  qIndex++;
  if(qIndex>=10){
    view="result";
    render();
    return;
  }

  firstWrong=false;
  wrongChoices=new Set();
  current=makeQuestion();
  locked=false;
  render();
}

let failureAnimationToken = 0;

function animateFailureMascot(){
  const mascotEl = document.getElementById("quizMascot");
  if(!mascotEl) return;

  const token = ++failureAnimationToken;
  mascotEl.classList.remove("mascot-no");
  void mascotEl.offsetWidth;
  mascotEl.classList.add("mascot-no");

  setTimeout(()=>{
    if(token !== failureAnimationToken) return;
    const liveMascot = document.getElementById("quizMascot");
    if(liveMascot) liveMascot.classList.remove("mascot-no");
  }, 1050);
}

function showFeedback(type){
  if(type !== "success") return;

  feedbackLayer.className = "feedback-layer show-success";
  feedbackLayer.innerHTML = `<img src="${mascot.success}" alt=""><div class="feedback-bubble">${t("great")}</div>`;

  const img = feedbackLayer.querySelector("img");
  if(!img) return;

  img.style.animation = "none";
  img.style.opacity = "0";
  img.style.bottom = "-230px";

  const variants = ["left", "right", "vertical"];
  const variant = variants[Math.floor(Math.random() * variants.length)];
  const width = window.innerWidth;
  const height = window.innerHeight;
  const startX = variant === "left" ? -Math.min(width * 0.32, 360) :
                 variant === "right" ? Math.min(width * 0.32, 360) : 0;
  const endX = variant === "left" ? Math.min(width * 0.18, 220) :
               variant === "right" ? -Math.min(width * 0.18, 220) : 0;
  const apex = Math.min(height * 0.70, height - 100);
  const duration = 1900;
  const started = performance.now();

  function frame(now){
    const p = Math.min(1, (now - started) / duration);
    const smoothP = p * p * (3 - 2 * p);
    const x = startX + (endX - startX) * smoothP;
    const y = -4 * apex * p * (1 - p);
    const scale = 0.86 + 0.18 * Math.sin(Math.PI * p);
    const rotation = variant === "left" ? -8 + 18 * smoothP :
                     variant === "right" ? 8 - 18 * smoothP : 0;
    const flip = variant === "right" ? -1 : 1;

    let opacity = 1;
    if(p < 0.06) opacity = p / 0.06;
    else if(p > 0.93) opacity = Math.max(0, (1 - p) / 0.07);

    img.style.opacity = String(opacity);
    img.style.transform = `translate3d(${x}px, ${y}px, 0) scaleX(${flip}) scale(${scale}) rotate(${rotation}deg)`;

    if(p < 1){
      requestAnimationFrame(frame);
    } else {
      feedbackLayer.className = "feedback-layer";
      feedbackLayer.innerHTML = "";
    }
  }

  requestAnimationFrame(frame);
}

function renderResult(){
  app.innerHTML = `
    <section class="panel result-card">
      <img class="result-mascot" src="${mascot.main}" alt="">
      <p class="result-score">${good}/10</p>
      <h2>${t("resultTitle")}</h2>
      <p>${t("correct")}: ${good} · ${t("wrong")}: ${bad}<br>${t("resultText")}</p>
      <div class="actions" style="justify-content:center">
        <button class="primary" onclick="startQuiz('${mode}', quizBackTarget)">${t("again")}</button>
        <button class="secondary" onclick="go('choose')">${t("chooseAnother")}</button>
        <button class="secondary" onclick="go('home')">${t("home")}</button>
      </div>
    </section>`;
}

// Pong
let pongRAF = null;
function renderPong(){
  if(pongRAF) cancelAnimationFrame(pongRAF);
  // Choices/New game rebuild this view. Keep the independently scrolled
  // desktop controls in place instead of jumping back to the mascot each time.
  const desktopControlsScroll = !isPongMobileDevice()
    ? (document.querySelector(".pong-side")?.scrollTop || 0)
    : 0;
  app.innerHTML = `
    <section class="panel pong-panel">
      <div class="back-row pong-header-row">
        <div class="pong-desktop-toolbar">
        ${backButton("home")}
        <div class="pong-header-center" id="pongHeaderCenter" dir="${lang === "he" ? "rtl" : "ltr"}">
          <div class="pong-status-slot" role="status" aria-live="polite" aria-atomic="true">
            <div id="pongHeaderScore" class="pong-live-score" dir="ltr">
              <span class="pong-live-player"><strong data-pong-score="user">0</strong><small dir="${lang === 'he' ? 'rtl' : 'ltr'}">${t("you")}:</small></span>
              <span class="pong-live-separator" aria-hidden="true"></span>
              <span class="pong-live-player"><strong data-pong-score="ai">0</strong><small dir="${lang === 'he' ? 'rtl' : 'ltr'}">${t("minik")}:</small></span>
            </div>
            <span id="pongHeaderMessage" class="pong-header-message" hidden></span>
          </div>
          <button
            id="pongMadnessToggle"
            data-pong-madness-toggle
            class="pong-madness-toggle ${pongBalloonMadness ? "active" : ""}"
            type="button"
            role="checkbox"
            aria-checked="${pongBalloonMadness ? "true" : "false"}"
            onclick="toggleBalloonMadness()"
          >${t("balloonMadness")}</button>
        </div>
        </div>
        <button class="pong-mobile-new" type="button" onclick="resetPong()">${t("pongNew")}</button>
        <span class="pong-badge">🏓 ${t("pongTitle")}</span>
      </div>
          <div class="pong-landscape-hud">
            ${backButton("home")}
            <div class="pong-landscape-center" dir="${lang === "he" ? "rtl" : "ltr"}">
              <div class="pong-status-slot" role="status" aria-live="polite" aria-atomic="true">
                <div id="pongLandscapeScore" class="pong-landscape-score pong-live-score" dir="ltr">
                  <span class="pong-live-player"><strong id="landscapeUserScore" data-pong-score="user">0</strong><small dir="${lang === 'he' ? 'rtl' : 'ltr'}">${t("you")}:</small></span>
                  <span class="pong-live-separator" aria-hidden="true"></span>
                  <span class="pong-live-player"><strong id="landscapeAiScore" data-pong-score="ai">0</strong><small dir="${lang === 'he' ? 'rtl' : 'ltr'}">${t("minik")}:</small></span>
                </div>
                <div id="pongLandscapeMessage" class="pong-landscape-message" hidden></div>
              </div>
              <button id="pongLandscapeMadnessToggle" data-pong-madness-toggle
                class="pong-madness-toggle ${pongBalloonMadness ? "active" : ""}"
                type="button" role="checkbox" aria-checked="${pongBalloonMadness}"
                onclick="toggleBalloonMadness()">${t("balloonMadness")}</button>
            </div>
            <button class="pong-landscape-new" type="button" onclick="resetPong()">${t("pongNew")}</button>
          </div>
      <div class="pong-wrap">
        <div class="canvas-card">
          <div class="pong-playfield"><canvas id="pongCanvas" width="900" height="560"></canvas><div id="pongLandscapeCountdown" class="pong-landscape-countdown" hidden>3</div></div>
          <div class="pong-infield-hud" aria-label="${t('you')} / ${t('minik')}">
            <div class="pong-infield-back">${backButton("home")}</div>
            <div class="pong-mini-score" dir="ltr"><span><b data-pong-score="user">0</b><small dir="${lang === 'he' ? 'rtl' : 'ltr'}">${t('you')}:</small></span><span aria-hidden="true"></span><span><b data-pong-score="ai">0</b><small dir="${lang === 'he' ? 'rtl' : 'ltr'}">${t('minik')}:</small></span></div>
            <button class="pong-infield-help pong-help-button" type="button" onclick="PongExtras.openSettings(false)" aria-label="${lang === 'he' ? 'עזרה והגדרות' : 'Help & settings'}">⚙</button>
            <span class="pong-mini-total" dir="ltr"><small dir="${lang === 'he' ? 'rtl' : 'ltr'}">${lang === 'he' ? 'מצטבר' : 'Total'}:</small><b data-total-points>0</b></span>
            <button class="pong-infield-new" type="button" onclick="resetPong()">${t("pongNew")}</button>
          </div>
          <div id="pongLandscapeSetup" class="pong-landscape-setup" aria-labelledby="pongSetupTitle">
            <header class="pong-setup-header">
              <div class="pong-setup-nav">${backButton("home")}</div>
              <h2 id="pongSetupTitle" class="pong-setup-title">${t("setupTitle")}</h2>
              <img class="pong-setup-logo" src="${useStandalonePongBrand ? "assets/minik-brand.png" : mascot.logo}" alt="${useStandalonePongBrand ? "Minik Ping Pong" : "Minik Math"}" draggable="false">
            </header>
            <div class="pong-setup-body">
              <img class="pong-landscape-art" src="${mascot.pong}" alt="${t("pongTitle")}">
              <div class="pong-landscape-setup-controls">
                <div class="pong-landscape-difficulty pong-landscape-control-row">
                  <span>${t("difficulty")}</span>
                  <div class="pong-difficulty-buttons">
                    <button type="button" data-level="beginner" onclick="setPongDifficulty('beginner')" class="${pongDifficulty==="beginner" ? "active" : ""}">${t("beginner")}</button>
                    <button type="button" data-level="medium" onclick="setPongDifficulty('medium')" class="${pongDifficulty==="medium" ? "active" : ""}">${t("medium")}</button>
                    <button type="button" data-level="hard" onclick="setPongDifficulty('hard')" class="${pongDifficulty==="hard" ? "active" : ""}">${t("hard")}</button>
                  </div>
                </div>
                <label class="pong-target-row pong-landscape-control-row">
                  <span class="pong-target-label">${t("targetScore")}</span>
                  <select class="pong-target-select" data-target-score-select onchange="setPongTargetScore(this.value)">
                    ${[3,5,7,11].map(score=>`<option value="${score}" ${pongTargetScore===score ? "selected" : ""}>${score}</option>`).join("")}
                  </select>
                </label>
                <div class="pong-landscape-madness pong-landscape-control-row">
                  <span class="pong-setup-label" id="pongMadnessLabel">${t("balloonMadness")}:</span>
                  <div class="pong-madness-options" role="group" aria-labelledby="pongMadnessLabel">
                    <button type="button" data-pong-madness-value="true" aria-pressed="${pongBalloonMadness}" class="${pongBalloonMadness ? "active" : ""}" onclick="setBalloonMadness(true)">${t("yes")}</button>
                    <button type="button" data-pong-madness-value="false" aria-pressed="${!pongBalloonMadness}" class="${!pongBalloonMadness ? "active" : ""}" onclick="setBalloonMadness(false)">${t("no")}</button>
                  </div>
                </div>
              </div>
            </div>
            <div class="pong-setup-actions">
              <button class="primary pong-landscape-start" type="button" onclick="startPongLandscape()">${t("restart")}</button>
            </div>
          </div>

        </div>
        <div class="pong-control-dock" id="pongControlDock"></div>
        <aside class="pong-side">
          <div class="scorebox pong-scorebox">
            <div class="pong-score-visual">
              <img class="pong-art" src="${mascot.pong}" alt="${t("pongTitle")}">
            </div>
            <div class="pong-table-size" aria-label="${t("pongTableSize")}">
              <span class="pong-table-size-label">${t("pongTableSize")}</span>
              <div class="pong-table-size-buttons">
                <button type="button" data-pong-size="1.5" onclick="setPongTableSize(1.5)" class="${pongMobileHeightScale===1.5 ? "active" : ""}">${t("pongSizeSmall")}</button>
                <button type="button" data-pong-size="2" onclick="setPongTableSize(2)" class="${pongMobileHeightScale===2 ? "active" : ""}">${t("pongSizeMedium")}</button>
                <button type="button" data-pong-size="2.5" onclick="setPongTableSize(2.5)" class="${pongMobileHeightScale===2.5 ? "active" : ""}">${t("pongSizeLarge")}</button>
              </div>
            </div>
            <div class="pong-score-grid" dir="ltr">
              <div class="pong-score-player">
                <strong id="userScore">0</strong>
                <span dir="${lang === 'he' ? 'rtl' : 'ltr'}">${t("you")}:</span>
              </div>
              <span class="pong-score-separator" aria-hidden="true"></span>
              <div class="pong-score-player">
                <strong id="aiScore">0</strong>
                <span dir="${lang === 'he' ? 'rtl' : 'ltr'}">${t("minik")}:</span>
              </div>
            </div>
          </div>
          <div class="scorebox help">${pongHelpText()}</div>
          <div class="pong-difficulty" aria-label="${t("difficulty")}">
            <span class="pong-difficulty-label">${t("difficulty")}</span>
            <div class="pong-difficulty-buttons">
              <button type="button" data-level="beginner" onclick="setPongDifficulty('beginner')" class="${pongDifficulty==="beginner" ? "active" : ""}">${t("beginner")}</button>
              <button type="button" data-level="medium" onclick="setPongDifficulty('medium')" class="${pongDifficulty==="medium" ? "active" : ""}">${t("medium")}</button>
              <button type="button" data-level="hard" onclick="setPongDifficulty('hard')" class="${pongDifficulty==="hard" ? "active" : ""}">${t("hard")}</button>
            </div>
            <label class="pong-target-row pong-target-inline">
              <span class="pong-target-label">${t("targetScore")}</span>
              <select class="pong-target-select" data-target-score-select onchange="setPongTargetScore(this.value)">
                ${[3,5,7,11].map(score=>`<option value="${score}" ${pongTargetScore===score ? "selected" : ""}>${score}</option>`).join("")}
              </select>
            </label>
          <div class="pong-pc-orientation">
            <span class="pong-pc-orientation-label">${t("gameDirection")}</span>
            <div class="pong-pc-orientation-buttons">
              <button type="button" data-pong-orientation="vertical" onclick="setPongPcOrientation('vertical')" class="${pongPcOrientation==='vertical' ? 'active' : ''}">${t("bottomTop")}</button>
              <button type="button" data-pong-orientation="horizontal" onclick="setPongPcOrientation('horizontal')" class="${pongPcOrientation==='horizontal' ? 'active' : ''}">${t("sideToSide")}</button>
            </div>
          </div>
          </div>
          <button class="primary" onclick="resetPong()">${t("restart")}</button>
        </aside>
      </div>
    </section>`;
  initPong();
  if(!isPongMobileDevice()){
    document.querySelector(".pong-side").scrollTop = desktopControlsScroll;
  }
}

let pong;
const PONG_PADDLE_WIDTH = 18;
const PONG_PADDLE_HEIGHT = 112;
function resolvedPongPaddleHeight(canvas){
  if(/MinikNative\/Android/i.test(navigator.userAgent||"")){
    const factor=window.PongExtras?.paddleLengthFactor?.()||1;
    const axis=canvas?(isPongMobileLandscape()?canvas.width:canvas.height):PONG_PADDLE_HEIGHT;
    const baseline=canvas&&isPongMobileLandscape()
      ? Math.max(64,Math.min(92,Math.round(canvas.height*.24)))
      : PONG_PADDLE_HEIGHT;
    return Math.max(24,Math.min(Math.round(baseline*factor),Math.round(axis*.78)));
  }
  if(canvas && isPongMobileLandscape()){
    return Math.max(64, Math.min(92, Math.round(canvas.height * 0.24)));
  }
  return PONG_PADDLE_HEIGHT;
}
const PONG_BALL_RADIUS = 13.5;
const PONG_STALL_HIT_LIMIT = 10;
const PONG_STALL_VY_THRESHOLD = 0.70;
const PONG_STALL_RELEASE_VY = 1.65;
const PONG_POINT_PAUSE_MS = 650;
const PONG_POINT_FLASH_STEP_MS = 170;
const PONG_CHAOS_FLASH_MS = 820;
const PONG_MADNESS_MAX_BALLOONS = 3;
const PONG_MADNESS_MAX_OBJECTS = 5;
const PONG_MADNESS_MAX_EXTRA = 2;
const PONG_MADNESS_EXTRA_DELAY_MS = 20000;

const PONG_PALETTES = [
  { user: "#69d8a8", ai: "#f58cc8" },
  { user: "#4da3ff", ai: "#ffd84d" },
  { user: "#ff8a3d", ai: "#f0d7a6" }
];
let lastPongPaletteIndex = -1;
const pongUrlParams = new URLSearchParams(window.location.search);
let pongBalloonMadness = window.PongExtras?.matchSettings?.().balloonMadness ?? (pongUrlParams.get("madness") !== "off");

const PONG_MADNESS_BALLOON_SRCS = [
  "assets/balloon1.webp",
  "assets/balloon2.webp",
  "assets/balloon3.webp",
  "assets/balloon4.webp",
  "assets/balloon5.webp",
  "assets/balloon6.webp",
  "assets/balloon7.webp",
  "assets/balloon8.webp"
];
const PONG_MADNESS_BEACH_BALL_SRC = "assets/s05_beach_ball_round.webp";
const PONG_MADNESS_COTTON_BALL_SRC = "assets/cotton_candy_ball.webp";
const PONG_MADNESS_CLOUD_SRCS = [
  "assets/cloud_blue_a.webp",
  "assets/cloud_yellow.webp",
  "assets/cloud_blue_b.webp"
];
const PONG_MADNESS_CAR_SRC = "assets/minik_rainbow_car.webp";

function loadPongMadnessImage(src){
  const image = new Image();
  image.decoding = "async";
  image.src = src;
  return image;
}

const pongMadnessImages = {
  balloons: PONG_MADNESS_BALLOON_SRCS.map(loadPongMadnessImage),
  beachBall: loadPongMadnessImage(PONG_MADNESS_BEACH_BALL_SRC),
  cottonBall: loadPongMadnessImage(PONG_MADNESS_COTTON_BALL_SRC),
  clouds: PONG_MADNESS_CLOUD_SRCS.map(loadPongMadnessImage),
  car: loadPongMadnessImage(PONG_MADNESS_CAR_SRC)
};

function pongRandom(min,max){
  return min + Math.random() * (max - min);
}

function nextPongPalette(){
  if(lastPongPaletteIndex < 0){
    lastPongPaletteIndex = 0;
    return PONG_PALETTES[0];
  }
  let nextIndex = lastPongPaletteIndex;
  while(nextIndex === lastPongPaletteIndex){
    nextIndex = Math.floor(Math.random() * PONG_PALETTES.length);
  }
  lastPongPaletteIndex = nextIndex;
  return PONG_PALETTES[nextIndex];
}

let pongDifficulty = window.PongExtras?.difficulty?.() || "beginner";
let pongTargetScore = window.PongExtras?.matchSettings?.().targetScore || 5;
let pongPcOrientation = "vertical";
let pongMobileHeightScale = 2.5;
let pongMobileStartRequested = false;
let pongSessionStarted = false;
let pongLandscapeCountdownRequested = false;

function syncPongMadnessControls(){
  document.querySelectorAll("[data-pong-madness-value]").forEach(button=>{
    const selected = (button.dataset.pongMadnessValue === "true") === pongBalloonMadness;
    button.classList.toggle("active", selected);
    button.setAttribute("aria-pressed", String(selected));
  });
  document.querySelectorAll("[data-pong-madness-toggle]").forEach(toggle => {
    toggle.classList.toggle("active", pongBalloonMadness);
    toggle.setAttribute("aria-checked", pongBalloonMadness ? "true" : "false");
  });
}

function syncPongHeaderState(){
  // Score/outcome owns one slot. Madness is a separate, always usable control,
  // including after match end; toggling it must not restart or clear the result.
  syncPongMadnessControls();
  syncPongCompactState();
  const showOutcome = !!pong && pong.over && !pong.resultsPending;
  const outcomeText = showOutcome
    ? (pong.userScore > pong.aiScore ? t("win") : t("lose"))
    : "";
  for(const [scoreId, messageId] of [
    ["pongHeaderScore", "pongHeaderMessage"],
    ["pongLandscapeScore", "pongLandscapeMessage"]
  ]){
    const score = document.getElementById(scoreId);
    const message = document.getElementById(messageId);
    if(score) score.hidden = showOutcome;
    if(message){
      message.hidden = !showOutcome;
      message.textContent = outcomeText;
    }
  }
}

function resetPongMadnessTimeline(now){
  if(!pong) return;
  pong.madnessActivatedAt = pongBalloonMadness ? now : 0;
  pong.nextBalloonSpawnAt = now + pongRandom(450, 900);
  pong.nextMiscSpawnAt = now + PONG_MADNESS_EXTRA_DELAY_MS + pongRandom(600, 1800);
}

window.setBalloonMadness = enabled=>{
  if(typeof enabled !== "boolean" || enabled === pongBalloonMadness) return;
  pongBalloonMadness = enabled;
  window.PongExtras?.setMatchSettings({balloonMadness:enabled});
  const now = performance.now();

  if(pong){
    pong.c.classList.toggle("balloon-madness", pongBalloonMadness);
    pong.madnessObjects = [];
    resetPongMadnessTimeline(now);
  }

  syncPongHeaderState();
};
window.toggleBalloonMadness = ()=>setBalloonMadness(!pongBalloonMadness);

const pongDifficultySettings = {
  hard: {
    aiSpeed: 5.1,
    slowSpeed: 5.1,
    slowChance: 0.00,
    reactionFrames: 1,
    missChance: 0.00,
    missOffset: 0
  },
  medium: {
    aiSpeed: 4.30,
    slowSpeed: 3.75,
    slowChance: 0.15,
    reactionFrames: 3,
    missChance: 0.10,
    missOffset: 130
  },
  beginner: {
    aiSpeed: 3.45,
    slowSpeed: 2.75,
    slowChance: 0.42,
    reactionFrames: 6,
    missChance: 0.30,
    missOffset: 220
  }
};

window.setPongDifficulty = level => {
  if(!pongDifficultySettings[level]) return;
  pongDifficulty = level;
  window.PongExtras?.setDifficulty(level);
  document.querySelectorAll(".pong-difficulty-buttons button").forEach(button => {
    button.classList.toggle("active", button.dataset.level === level);
  });
  if(pong){
    pong.aiTargetY = pong.c.height / 2;
    pong.aiReactionCounter = 0;
    const settings = pongDifficultySettings[level];
    pong.aiForcedMiss = Math.random() < settings.missChance;
    pong.aiMissDirection = Math.random() < 0.5 ? -1 : 1;
    pong.aiSlowRally = Math.random() < settings.slowChance;
  }
};

window.setPongTargetScore = score => {
  const next = Number(score);
  if(![3,5,7,11].includes(next)) return;
  pongTargetScore = next;
  window.PongExtras?.setMatchSettings({targetScore:next});
  document.querySelectorAll("[data-target-score-select]").forEach(select => {
    select.value = String(next);
  });
  const help = document.querySelector(".scorebox.help");
  if(help) help.textContent = pongHelpText();
};

window.setPongPcOrientation = orientation => {
  if(!["vertical","horizontal"].includes(orientation)) return;
  pongPcOrientation = orientation;
  if(view === "pong" && !isPongMobileDevice()) renderPong();
};

function isPongPcVertical(){
  return !isPongMobileDevice() && pongPcOrientation === "vertical";
}

// The drawing surface spans the screen; controls constrain gameplay, not artwork.
// DOM rectangles are CSS pixels and are converted into canvas coordinates once
// after layout/resize. Nothing measures the DOM on an animation frame.
function calculatePongCourtBounds(width,height,rect,buttons,thickness,gap=8){
  let min=0,max=width;
  if(!(rect.width>0&&rect.height>0))return {min,max};
  const scaleX=width/rect.width,scaleY=rect.height/height;
  const paddleTop=rect.top+(height-16-thickness)*scaleY;
  const paddleBottom=rect.top+(height-16)*scaleY;
  for(const button of buttons){
    if(!(button.width>0&&button.height>0)||button.bottom<=paddleTop||button.top>=paddleBottom)continue;
    if(button.left+button.width/2<rect.left+rect.width/2){
      min=Math.max(min,(button.right-rect.left+gap)*scaleX);
    }else{
      max=Math.min(max,(button.left-rect.left-gap)*scaleX);
    }
  }
  min=Math.max(0,Math.min(width,min));max=Math.max(min,Math.min(width,max));
  return {min,max};
}
function getPongCourtBounds(){
  if(pong.pcVertical&&pong.courtBounds)return pong.courtBounds;
  return {min:0,max:pong.pcVertical?pong.c.width:pong.c.height};
}
function clampPongPaddle(position){
  const bounds=getPongCourtBounds();
  return Math.max(bounds.min,Math.min(bounds.max-pong.paddleHeight,position));
}
function refreshPongCourtBounds(){
  if(!pong)return;
  const c=pong.c;
  pong.courtBounds={min:0,max:c.width};
  if(pong.pcVertical&&/MinikNative\/Android/i.test(navigator.userAgent||"")&&isPongMobileLandscape()){
    const rect=c.getBoundingClientRect();
    const buttons=[...document.querySelectorAll('#pongExtraControls .pong-arrow')]
      .filter(b=>!b.hidden).map(b=>b.getBoundingClientRect());
    pong.courtBounds=calculatePongCourtBounds(c.width,c.height,rect,buttons,PONG_PADDLE_WIDTH);
    pong.paddleHeight=Math.min(pong.paddleHeight,Math.max(1,pong.courtBounds.max-pong.courtBounds.min));
  }
  pong.userY=clampPongPaddle(pong.userY);pong.aiY=clampPongPaddle(pong.aiY);
  pong.aiTargetY=pong.aiY+pong.paddleHeight/2;
  if(pong.pcVertical){
    const {min,max}=getPongCourtBounds();
    pong.ball.x=Math.max(min+pong.ball.r,Math.min(max-pong.ball.r,pong.ball.x));
  }
}

function initPong(){
  window.MinikAudio?.stopAll();
  window.PongExtras?.prepareRound?.();
  const c=document.getElementById("pongCanvas");
  const canvasCard = c.closest(".canvas-card");
  const isMobilePong = isPongMobileDevice();
  const isLandscapePong = isPongMobileLandscape();
  const pcVertical = isLandscapePong || (!isMobilePong && pongPcOrientation === "vertical");
  const requestedStart = pongMobileStartRequested;
  const requestedLandscapeCountdown = isMobilePong && (pongLandscapeCountdownRequested || (pongSessionStarted && !requestedStart));
  const shouldWaitForStart = isMobilePong && !requestedStart && !pongSessionStarted;
  if(!shouldWaitForStart)pongSessionStarted=true;
  pongMobileStartRequested = false;
  pongLandscapeCountdownRequested = false;

  // Desktop size comes from the available grid track, not sidebar content.
  // Its canvas buffer is measured below, so the ball remains round.

  if(isMobilePong && canvasCard){
    const baseWidth = Math.max(240, Math.round(canvasCard.getBoundingClientRect().width));
    const mobileMinHeight = Math.max(160, Math.round(baseWidth * 560 / 900));
    const requestedHeight = Math.round(mobileMinHeight * pongMobileHeightScale);
    canvasCard.style.setProperty("--pong-mobile-height", `${requestedHeight}px`);
    canvasCard.classList.add("pong-height-adjusted");
    c.classList.add("pong-height-adjusted");
  }

  document.body.classList.toggle("pong-waiting", shouldWaitForStart);
  window.PongExtras?.prepareLayout(pcVertical);
  const displayed = c.getBoundingClientRect();
  c.width = Math.max(1, Math.round(displayed.width));
  c.height = Math.max(1, Math.round(displayed.height));

  const now = performance.now();
  const ctx=c.getContext("2d");
  const initialPaddleHeight = resolvedPongPaddleHeight(c);
  const initialPaddleHalf = initialPaddleHeight / 2;
  const initialAxisExtent = pcVertical ? c.width : c.height;
  pong={
    monetizationId:window.MinikMonetization.begin("retro"),
    resultsPending:false,
    c,ctx,
    pcVertical,
    paddleHeight:initialPaddleHeight,
    userY:initialAxisExtent/2-initialPaddleHalf,
    aiY:initialAxisExtent/2-initialPaddleHalf,
    aiTargetY:initialAxisExtent/2,
    aiReactionCounter:0,
    aiForcedMiss:Math.random() < pongDifficultySettings[pongDifficulty].missChance,
    aiMissDirection:Math.random() < 0.5 ? -1 : 1,
    aiSlowRally:Math.random() < pongDifficultySettings[pongDifficulty].slowChance,
    flatHitCount:0,
    rallyHitCount:0,
    rallyStartedAt:now,
    ballChaosUntil:0,
    repeatedContactCount:0,
    lastContactBySide:{ user:null, ai:null },
    lastPaddleContact:null,
    userScore:0,
    aiScore:0,
    over:false,
    waitingForStart:shouldWaitForStart,
    startCountdownUntil:requestedLandscapeCountdown ? now + 3000 : 0,
    simulationNow:now,
    palette:{...nextPongPalette()},
    pointScorer:null,
    pointPauseStartedAt:0,
    pointPauseUntil:0,
    pendingResetDirection:0,
    pendingMatchEnd:false,
    madnessObjects:[],
    madnessActivatedAt:pongBalloonMadness ? now : 0,
    nextBalloonSpawnAt:now + pongRandom(500, 1100),
    nextMiscSpawnAt:now + PONG_MADNESS_EXTRA_DELAY_MS + pongRandom(700, 1800),
    lastFrameAt:now,
    ball:{
      x:c.width/2,
      y:c.height/2,
      vx:(shouldWaitForStart || requestedLandscapeCountdown) ? 0 : (pcVertical ? 3.4 : 6),
      vy:(shouldWaitForStart || requestedLandscapeCountdown) ? 0 : (pcVertical ? -6 : 3.4),
      r:PONG_BALL_RADIUS
    }
  };
  c.classList.toggle("balloon-madness", pongBalloonMadness);
  document.body.classList.toggle("pong-waiting", shouldWaitForStart);
  document.body.classList.toggle("pong-countdown", requestedLandscapeCountdown);
  document.body.classList.toggle("pong-playing", !shouldWaitForStart);

  window.setPongTableSize = scale => {
    if(!isMobilePong || !canvasCard || !pong) return;

    const allowed = [1.5, 2, 2.5];
    const nextScale = allowed.includes(Number(scale)) ? Number(scale) : 1.5;
    pongMobileHeightScale = nextScale;

    document.querySelectorAll(".pong-table-size-buttons button").forEach(button => {
      button.classList.toggle("active", Number(button.dataset.pongSize) === nextScale);
    });

    const oldWidth = c.width;
    const oldHeight = c.height;
    const userCenterRatio = oldHeight ? (pong.userY + pong.paddleHeight/2) / oldHeight : 0.5;
    const aiCenterRatio = oldHeight ? (pong.aiY + pong.paddleHeight/2) / oldHeight : 0.5;
    const ballXRatio = oldWidth ? pong.ball.x / oldWidth : 0.5;
    const ballYRatio = oldHeight ? pong.ball.y / oldHeight : 0.5;

    const baseHeight = Math.max(160, Math.round(c.getBoundingClientRect().width * 560 / 900));
    const requestedHeight = Math.round(baseHeight * nextScale);
    canvasCard.style.setProperty("--pong-mobile-height", `${requestedHeight}px`);

    const rect = c.getBoundingClientRect();
    c.width = Math.max(1, Math.round(rect.width));
    c.height = Math.max(1, Math.round(rect.height));

    pong.userY = Math.max(0, Math.min(c.height-pong.paddleHeight, userCenterRatio * c.height - pong.paddleHeight/2));
    pong.aiY = Math.max(0, Math.min(c.height-pong.paddleHeight, aiCenterRatio * c.height - pong.paddleHeight/2));
    pong.aiTargetY = pong.aiY + pong.paddleHeight/2;
    pong.ball.x = Math.max(pong.ball.r, Math.min(c.width - pong.ball.r, ballXRatio * c.width));
    pong.ball.y = Math.max(pong.ball.r, Math.min(c.height - pong.ball.r, ballYRatio * c.height));

    if(pongBalloonMadness){
      pong.madnessObjects = [];
      const resetNow = performance.now();
      pong.nextBalloonSpawnAt = resetNow + pongRandom(450, 900);
      pong.nextMiscSpawnAt = Math.max(
        resetNow + pongRandom(1600, 2600),
        pong.madnessActivatedAt + PONG_MADNESS_EXTRA_DELAY_MS + pongRandom(300, 900)
      );
    }
  };

  const setPaddleFromPointer = (clientX,clientY)=>{
    const r=c.getBoundingClientRect();
    if(pong.pcVertical){
      const x=(clientX-r.left)*(c.width/r.width);
      pong.userY=clampPongPaddle(x-pong.paddleHeight/2);
    }else{
      const y=(clientY-r.top)*(c.height/r.height);
      pong.userY=clampPongPaddle(y-pong.paddleHeight/2);
    }
  };
  c.onmousemove=e=>{if(!window.PongExtras || PongExtras.canUsePointer("mouse")) setPaddleFromPointer(e.clientX,e.clientY);};
  c.onpointermove=e=>{
    if((e.pointerType==="touch" || e.pointerType==="pen") && (!window.PongExtras || PongExtras.canUsePointer("touch"))) setPaddleFromPointer(e.clientX,e.clientY);
  };
  c.ontouchmove=e=>{if(!window.PongExtras || PongExtras.canUsePointer("touch")){e.preventDefault();setPaddleFromPointer(e.touches[0].clientX,e.touches[0].clientY);}};

  lastPongLandscapeMode = isPongMobileLandscape();
  syncPongLandscapeClass();
  syncPongHeaderState();
  window.PongExtras?.mount();
  refreshPongCourtBounds();
  maybeShowPongOrientationHint();
  loopPong();
}

window.startPongLandscape = ()=>{
  if(view!=="pong") return;
  pongMobileStartRequested = true;
  pongLandscapeCountdownRequested = true;
  renderPong();
};

window.openPongLandscapeSetup = ()=>{
  if(view!=="pong") return;
  pongMobileStartRequested = false;
  pongLandscapeCountdownRequested = false;
  renderPong();
};

window.resetPong=()=>{
  if(view!=="pong")return;
  pongMobileStartRequested=true;
  pongLandscapeCountdownRequested=true;
  renderPong();
};

function resetBall(direction){
  const serveDirection = direction || (Math.random() < 0.5 ? -1 : 1);
  pong.ball = pong.pcVertical
    ? {x:pong.c.width/2,y:pong.c.height/2,vx:(Math.random()*6-3)||2,vy:6*serveDirection,r:PONG_BALL_RADIUS}
    : {x:pong.c.width/2,y:pong.c.height/2,vx:6*serveDirection,vy:(Math.random()*6-3)||2,r:PONG_BALL_RADIUS};
  pong.aiReactionCounter = 0;
  const settings = pongDifficultySettings[pongDifficulty];
  pong.aiForcedMiss = Math.random() < settings.missChance;
  pong.aiMissDirection = Math.random() < 0.5 ? -1 : 1;
  pong.aiSlowRally = Math.random() < settings.slowChance;
  pong.flatHitCount = 0;
  pong.rallyHitCount = 0;
  pong.rallyStartedAt = performance.now();
  pong.ballChaosUntil = 0;
  pong.repeatedContactCount = 0;
  pong.lastContactBySide = { user:null, ai:null };
  pong.lastPaddleContact = null;
}

function flashPongScore(scorer){
  if(!pong) return;
  const player = scorer === "user" ? "user" : "ai";
  const legacyId = player === "user" ? "userScore" : "aiScore";
  const color = player === "user" ? pong.palette.user : pong.palette.ai;
  document.querySelectorAll(`[data-pong-score="${player}"], #${legacyId}`).forEach(score=>{
    score.style.setProperty("--point-color", color);
    score.classList.remove("pong-point-flash");
    void score.offsetWidth;
    score.classList.add("pong-point-flash");
  });
}

function awardPongPoint(scorer, resetDirection, now){
  if(!pong || pong.over || pong.pointPauseUntil) return;

  if(scorer === "user"){ pong.userScore += 1; window.PongExtras?.awardPoint(); }
  else pong.aiScore += 1;
  // Match points only; train and balloon bonuses have their own sound hooks.
  window.MinikAudio?.play(scorer === "user" ? "success_sound" : "failure_sound", "pong-point");

  updatePongScore();
  flashPongScore(scorer);

  pong.pointScorer = scorer;
  pong.pointPauseStartedAt = now;
  pong.pointPauseUntil = now + PONG_POINT_PAUSE_MS;
  pong.pendingResetDirection = resetDirection;
  pong.pendingMatchEnd = pong.userScore >= pongTargetScore || pong.aiScore >= pongTargetScore;
  syncPongHeaderState();

  pong.ball.vx = 0;
  pong.ball.vy = 0;
  if(pong.pcVertical){
    pong.ball.y = scorer === "user" ? pong.ball.r : pong.c.height - pong.ball.r;
    pong.ball.x = Math.max(pong.ball.r, Math.min(pong.c.width - pong.ball.r, pong.ball.x));
  }else{
    pong.ball.x = scorer === "user" ? pong.c.width - pong.ball.r : pong.ball.r;
    pong.ball.y = Math.max(pong.ball.r, Math.min(pong.c.height - pong.ball.r, pong.ball.y));
  }
}

function finishPongPointPause(){
  if(!pong || !pong.pointPauseUntil) return;

  const matchEnded = pong.pendingMatchEnd;
  const resetDirection = pong.pendingResetDirection;

  pong.pointPauseStartedAt = 0;
  pong.pointPauseUntil = 0;
  pong.pendingResetDirection = 0;
  pong.pendingMatchEnd = false;
  pong.pointScorer = null;

  if(matchEnded){
    pong.over = true;
    pong.ball.x = pong.c.width / 2;
    pong.ball.y = pong.c.height / 2;
    pong.ball.vx = 0;
    pong.ball.vy = 0;
    const finished=pong;
    finished.resultsPending=true;
    try{localStorage.setItem("minik_last_completed_pong_match",JSON.stringify({id:finished.monetizationId,user:finished.userScore,minik:finished.aiScore}));}catch(_){}
    window.MinikMonetization.finish(finished.monetizationId,()=>{
      finished.resultsPending=false;
      if(pong===finished)syncPongHeaderState();
    });
    syncPongHeaderState();
    return;
  }

  resetBall(resetDirection);
}

function releaseFlatRally(){
  const secondary = pong.pcVertical ? pong.ball.vx : pong.ball.vy;
  if(Math.abs(secondary) < PONG_STALL_VY_THRESHOLD){
    pong.flatHitCount += 1;
  } else {
    pong.flatHitCount = 0;
  }
  if(pong.flatHitCount >= PONG_STALL_HIT_LIMIT){
    const direction = Math.random() < 0.5 ? -1 : 1;
    if(pong.pcVertical) pong.ball.vx = direction * PONG_STALL_RELEASE_VY;
    else pong.ball.vy = direction * PONG_STALL_RELEASE_VY;
    pong.flatHitCount = 0;
  }
}

function flashPongBallChaos(now, duration = PONG_CHAOS_FLASH_MS){
  if(!pong) return;
  pong.ballChaosUntil = Math.max(pong.ballChaosUntil || 0, now + duration);
}

function triggerPongChaosRelease(now){
  if(!pong || pong.pointPauseUntil || pong.over) return;
  const ball = pong.ball;
  const speed = Math.max(7, Math.hypot(ball.vx, ball.vy) || 7);
  const nextSpeed = Math.min(12, speed * pongRandom(1.02, 1.14));
  const angle = pongRandom(0.42, 0.95) * (Math.random() < 0.5 ? -1 : 1);
  const dir = Math.random() < 0.5 ? -1 : 1;
  ball.vx = Math.cos(angle) * nextSpeed * dir;
  ball.vy = Math.sin(angle) * nextSpeed;
  if(Math.abs(ball.vy) < 2.4){
    ball.vy = (Math.random() < 0.5 ? -1 : 1) * 2.4;
  }
  flashPongBallChaos(now, 1050);
  pong.flatHitCount = 0;
  pong.rallyHitCount = 0;
  pong.repeatedContactCount = 0;
  pong.lastContactBySide = { user:null, ai:null };
  pong.rallyStartedAt = now;
}

function recordPongPaddleContact(side, now){
  if(pong) pong.lastPaddleContact = side;
  if(!pong) return;
  window.MinikAudio?.play(side === "user" ? "minik_kick" : "minik_kick2", "pong-paddle");
  const ball = pong.ball;
  const axisExtent = pong.pcVertical ? pong.c.width : pong.c.height;
  const ballAxis = pong.pcVertical ? ball.x : ball.y;
  const mainVelocity = pong.pcVertical ? ball.vy : ball.vx;
  const secondaryVelocity = pong.pcVertical ? ball.vx : ball.vy;
  const paddleCenter = pong.userY + pong.paddleHeight/2;
  const center = side === "user" ? paddleCenter : pong.aiY + pong.paddleHeight/2;
  const sample = {
    y: ballAxis / Math.max(1, axisExtent),
    paddle: center / Math.max(1, axisExtent),
    slope: Math.abs(secondaryVelocity / Math.max(0.001, Math.abs(mainVelocity)))
  };
  const previous = pong.lastContactBySide[side];
  const sameLoop = previous && Math.abs(sample.y-previous.y)<0.022 && Math.abs(sample.paddle-previous.paddle)<0.022 && Math.abs(sample.slope-previous.slope)<0.075;
  pong.repeatedContactCount = sameLoop ? pong.repeatedContactCount + 1 : Math.max(0,pong.repeatedContactCount-1);
  pong.lastContactBySide[side] = sample;
  if(pong.repeatedContactCount >= 6) triggerPongChaosRelease(now);
}

function ensureBallVerticalChange(minRatio = 0.30){
  const ball = pong.ball;
  const speed = Math.max(3, Math.hypot(ball.vx, ball.vy));
  const minVy = speed * minRatio;
  if(Math.abs(ball.vy) < minVy){
    const signY = ball.vy === 0 ? (Math.random() < 0.5 ? -1 : 1) : Math.sign(ball.vy);
    const signX = ball.vx === 0 ? (Math.random() < 0.5 ? -1 : 1) : Math.sign(ball.vx);
    ball.vy = signY * minVy;
    ball.vx = signX * Math.sqrt(Math.max(0.1, speed * speed - ball.vy * ball.vy));
  }
}

function getPongMadnessCounts(){
  const counts = { total: pong.madnessObjects.length, balloons: 0, extra: 0 };
  for(const item of pong.madnessObjects){
    if(item.type === "balloon") counts.balloons += 1;
    else counts.extra += 1;
  }
  return counts;
}

function spawnPongBalloon(now){
  const counts = getPongMadnessCounts();
  if(counts.total >= PONG_MADNESS_MAX_OBJECTS || counts.balloons >= PONG_MADNESS_MAX_BALLOONS) return;

  const image = pongMadnessImages.balloons[Math.floor(Math.random() * pongMadnessImages.balloons.length)];
  const shortSide = Math.min(pong.c.width, pong.c.height);
  const width = shortSide * pongRandom(0.105, 0.155);
  const ratio = image.naturalWidth > 0 ? image.naturalHeight / image.naturalWidth : 1.65;
  const height = width * ratio;

  pong.madnessObjects.push({
    type:"balloon",
    image,
    x:pongRandom(width * 0.55, pong.c.width - width * 0.55),
    y:pong.c.height + height * 0.55,
    w:width,
    h:height,
    vy:-pongRandom(30, 58),
    drift:pongRandom(-12, 12),
    wobbleAmplitude:pongRandom(2.5, 8),
    wobbleSpeed:pongRandom(0.8, 1.6),
    phase:pongRandom(0, Math.PI * 2),
    spawnedAt:now
  });
}

function spawnPongBeachBall(now){
  const counts = getPongMadnessCounts();
  if(counts.total >= PONG_MADNESS_MAX_OBJECTS || counts.extra >= PONG_MADNESS_MAX_EXTRA) return;
  if(pong.madnessObjects.some(item => item.type === "beach")) return;

  const image = pongMadnessImages.beachBall;
  const shortSide = Math.min(pong.c.width, pong.c.height);
  const width = shortSide * pongRandom(0.21, 0.28);
  const ratio = image.naturalWidth > 0 ? image.naturalHeight / image.naturalWidth : 1;
  const height = width * ratio;

  pong.madnessObjects.push({
    type:"beach",
    image,
    x:pongRandom(width * 0.6, pong.c.width - width * 0.6),
    y:-height * 0.58,
    w:width,
    h:height,
    vy:pongRandom(28, 48),
    drift:pongRandom(-11, 11),
    hitCooldownUntil:0,
    spawnedAt:now
  });
}

function spawnPongCottonBall(now){
  const counts = getPongMadnessCounts();
  if(counts.total >= PONG_MADNESS_MAX_OBJECTS || counts.extra >= PONG_MADNESS_MAX_EXTRA) return;
  if(pong.madnessObjects.some(item => item.type === "cotton")) return;

  const image = pongMadnessImages.cottonBall;
  const shortSide = Math.min(pong.c.width, pong.c.height);
  const width = shortSide * pongRandom(0.18, 0.24);
  const ratio = image.naturalWidth > 0 ? image.naturalHeight / image.naturalWidth : 1;
  const height = width * ratio;

  pong.madnessObjects.push({
    type:"cotton",
    image,
    x:pongRandom(width * 0.6, pong.c.width - width * 0.6),
    y:-height * 0.58,
    w:width,
    h:height,
    vy:pongRandom(24, 42),
    drift:pongRandom(-7, 7),
    hitCooldownUntil:0,
    spawnedAt:now
  });
}

function spawnPongCloud(now){
  const counts = getPongMadnessCounts();
  if(counts.total >= PONG_MADNESS_MAX_OBJECTS || counts.extra >= PONG_MADNESS_MAX_EXTRA) return;

  const image = pongMadnessImages.clouds[Math.floor(Math.random() * pongMadnessImages.clouds.length)];
  const shortSide = Math.min(pong.c.width, pong.c.height);
  const width = shortSide * pongRandom(0.24, 0.34);
  const ratio = image.naturalWidth > 0 ? image.naturalHeight / image.naturalWidth : 0.58;
  const height = width * ratio;
  const fromLeft = Math.random() < 0.5;

  pong.madnessObjects.push({
    type:"cloud",
    image,
    x:fromLeft ? -width * 0.55 : pong.c.width + width * 0.55,
    y:pongRandom(height * 0.6, pong.c.height * 0.58),
    w:width,
    h:height,
    vx:fromLeft ? pongRandom(18, 30) : -pongRandom(18, 30),
    vy:pongRandom(-3.2, 3.2),
    wobbleAmplitude:pongRandom(4, 14),
    wobbleSpeed:pongRandom(0.25, 0.65),
    phase:pongRandom(0, Math.PI * 2),
    hitCooldownUntil:0,
    spawnedAt:now
  });
}

function spawnPongCar(now){
  const counts = getPongMadnessCounts();
  if(counts.total >= PONG_MADNESS_MAX_OBJECTS || counts.extra >= PONG_MADNESS_MAX_EXTRA) return;
  if(pong.madnessObjects.some(item => item.type === "car")) return;

  const image = pongMadnessImages.car;
  const shortSide = Math.min(pong.c.width, pong.c.height);
  const width = shortSide * pongRandom(0.28, 0.38);
  const ratio = image.naturalWidth > 0 ? image.naturalHeight / image.naturalWidth : 0.68;
  const height = width * ratio;
  const mirrored = Math.random() < 0.5;
  const diagonalSpeed = pongRandom(16, 26);

  pong.madnessObjects.push({
    type:"car",
    image,
    flipX:mirrored,
    x:mirrored ? pongRandom(pong.c.width * 0.68, pong.c.width - width * 0.24) : pongRandom(width * 0.24, pong.c.width * 0.32),
    y:-height * 0.55,
    w:width,
    h:height,
    vx:mirrored ? -diagonalSpeed : diagonalSpeed,
    vy:pongRandom(34, 50),
    hitCooldownUntil:0,
    spawnedAt:now
  });
}

function spawnRandomPongExtra(now){
  const counts = getPongMadnessCounts();
  if(counts.total >= PONG_MADNESS_MAX_OBJECTS || counts.extra >= PONG_MADNESS_MAX_EXTRA || counts.balloons < PONG_MADNESS_MAX_BALLOONS) return;

  const spawnLimit = Math.min(
    PONG_MADNESS_MAX_EXTRA - counts.extra,
    PONG_MADNESS_MAX_OBJECTS - counts.total,
    Math.random() < 0.58 ? 1 : 2
  );

  const spawners = [
    { fn: spawnPongCloud, weight: 3 },
    { fn: spawnPongBeachBall, weight: 2 },
    { fn: spawnPongCottonBall, weight: 2 },
    { fn: spawnPongCar, weight: 2 }
  ];

  for(let i=0; i<spawnLimit; i++){
    const bag = [];
    for(const entry of spawners){
      for(let n=0; n<entry.weight; n++) bag.push(entry.fn);
    }
    const pick = bag[Math.floor(Math.random() * bag.length)];
    pick(now + i * 12);
  }
}

function deflectPongBallSlightly(now){
  const ball = pong.ball;
  const speed = Math.max(3, Math.hypot(ball.vx, ball.vy));
  const vertical = pong.pcVertical;
  const main = vertical ? ball.vy : ball.vx;
  const side = vertical ? ball.vx : ball.vy;
  const sign = Math.sign(main) || 1;
  // Keep the previous maximum (~49 degrees), but don't draw a nearly-zero turn.
  const oldAngle = Math.atan2(side, Math.abs(main));
  const minimumTurn = 0.16; // ~9 degrees: noticeable, not a violent bounce.
  const turn = pongRandom(minimumTurn, 0.85);
  let nextAngle = oldAngle + (Math.random() < .5 ? -turn : turn);
  const limit = 1.14; // Retain useful speed toward the scoring axis.
  if(Math.abs(nextAngle) > limit) nextAngle = oldAngle - Math.sign(oldAngle || 1)*turn;
  nextAngle = Math.max(-limit, Math.min(limit, nextAngle));
  if(Math.abs(nextAngle-oldAngle) < minimumTurn){
    nextAngle = Math.max(-limit, Math.min(limit, oldAngle - Math.sign(oldAngle || 1)*minimumTurn));
  }
  const mainOut = sign * Math.cos(nextAngle)*speed;
  const sideOut = Math.sin(nextAngle)*speed;
  ball.vx = vertical ? sideOut : mainOut;
  ball.vy = vertical ? mainOut : sideOut;
  flashPongBallChaos(now, 720);
}

function bouncePongBallFromMovingObject(item, now){
  if(now < item.hitCooldownUntil) return;
  // After the physics cooldown gate: one cue per accepted beach/cotton/car hit,
  // not on every frame spent overlapping the same object. Clouds stay silent.
  const sound = item.type === "beach" || item.type === "cotton" ? "ball_hit" : "car_hit";
  window.MinikAudio?.play(sound, "pong-object");

  const ball = pong.ball;
  const incomingSign = Math.sign(ball.vx) || 1;
  ball.vx = -incomingSign * Math.max(4.5, Math.abs(ball.vx) * 1.02);
  ball.vy += pongRandom(-2.8, 2.8);
  ensureBallVerticalChange(0.26);

  if(item.type === "beach" || item.type === "cotton"){
    item.drift += incomingSign * pongRandom(16, 28);
    item.drift = Math.max(-44, Math.min(44, item.drift));
    item.vy *= pongRandom(0.97, 1.04);
  }else if(item.type === "car"){
    item.vx += incomingSign * pongRandom(2, 5);
  }

  item.hitCooldownUntil = now + 280;
  flashPongBallChaos(now, 720);
}

function applyCloudSpeedEffect(item, now){
  if(now < item.hitCooldownUntil) return;
  const ball = pong.ball;
  const speed = Math.hypot(ball.vx, ball.vy);
  if(speed < 1e-8) return;
  const slows = Math.random() < 0.5;
  let nextSpeed = Math.max(4.4, Math.min(12, speed * (slows ? pongRandom(0.82, 0.93) : pongRandom(1.08, 1.22))));
  if(Math.abs(nextSpeed - speed) < speed * 0.035){
    nextSpeed = Math.max(4.4, Math.min(12, speed * (slows ? 1.12 : 0.88)));
  }
  const ratio = nextSpeed / speed;
  ball.vx *= ratio; ball.vy *= ratio;
  item.hitCooldownUntil = now + 320;
  flashPongBallChaos(now, 720);
}

function pongObstacleCollision(item){
  let cx = item.x;
  let cy = item.y;
  let rx = item.w * 0.35 + pong.ball.r;
  let ry = item.h * 0.35 + pong.ball.r;

  if(item.type === "balloon"){
    cy = item.y - item.h * 0.18;
    rx = item.w * 0.36 + pong.ball.r;
    ry = item.h * 0.26 + pong.ball.r;
  }else if(item.type === "beach" || item.type === "cotton"){
    rx = item.w * 0.36 + pong.ball.r;
    ry = item.h * 0.36 + pong.ball.r;
  }else if(item.type === "cloud"){
    rx = item.w * 0.34 + pong.ball.r;
    ry = item.h * 0.24 + pong.ball.r;
  }else if(item.type === "car"){
    cy = item.y + item.h * 0.02;
    rx = item.w * 0.30 + pong.ball.r;
    ry = item.h * 0.24 + pong.ball.r;
  }

  const dx = pong.ball.x - cx;
  const dy = pong.ball.y - cy;
  return (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) <= 1;
}

function updatePongMadness(now,dt){
  if(!pongBalloonMadness){
    pong.madnessObjects = [];
    return;
  }

  const counts = getPongMadnessCounts();
  if(now >= pong.nextBalloonSpawnAt){
    if(counts.balloons < PONG_MADNESS_MAX_BALLOONS && counts.total < PONG_MADNESS_MAX_OBJECTS){
      spawnPongBalloon(now);
    }
    pong.nextBalloonSpawnAt = now + pongRandom(1700, 3000);
  }

  if(now - pong.madnessActivatedAt >= PONG_MADNESS_EXTRA_DELAY_MS && now >= pong.nextMiscSpawnAt){
    spawnRandomPongExtra(now);
    pong.nextMiscSpawnAt = now + pongRandom(2800, 4600);
  }

  const collisionsEnabled = !pong.over && !pong.waitingForStart && !pong.startCountdownUntil && !pong.pointPauseUntil;

  for(let i=pong.madnessObjects.length-1;i>=0;i--){
    const item = pong.madnessObjects[i];

    if(item.type === "balloon"){
      const age = (now - item.spawnedAt) / 1000;
      item.x += (item.drift + Math.sin(age * item.wobbleSpeed + item.phase) * item.wobbleAmplitude) * dt;
      item.y += item.vy * dt;

      if(item.y + item.h * 0.6 < -12 || item.x < -item.w || item.x > pong.c.width + item.w){
        pong.madnessObjects.splice(i,1);
        continue;
      }

      if(collisionsEnabled && pongObstacleCollision(item)){
        deflectPongBallSlightly(now);
        window.MinikAudio?.play("balloon_explode", "pong-object");
        if(pong.lastPaddleContact === "user") window.PongExtras?.awardPoints(1);
        pong.madnessObjects.splice(i,1);
        continue;
      }
    }else if(item.type === "cloud"){
      const age = (now - item.spawnedAt) / 1000;
      item.x += item.vx * dt;
      item.y += (item.vy + Math.sin(age * item.wobbleSpeed + item.phase) * item.wobbleAmplitude) * dt;
      item.y = Math.max(item.h * 0.48, Math.min(pong.c.height * 0.58, item.y));

      if((item.vx > 0 && item.x - item.w * 0.6 > pong.c.width + 12) || (item.vx < 0 && item.x + item.w * 0.6 < -12)){
        pong.madnessObjects.splice(i,1);
        continue;
      }

      if(collisionsEnabled && pongObstacleCollision(item)){
        applyCloudSpeedEffect(item, now);
      }
    }else{
      if(typeof item.drift === "number") item.x += item.drift * dt;
      if(typeof item.vx === "number") item.x += item.vx * dt;
      item.y += item.vy * dt;

      const half = item.w / 2;
      if(item.type === "beach" || item.type === "cotton"){
        if(item.x < half){
          item.x = half;
          item.drift = Math.abs(item.drift) * 0.7;
        }else if(item.x > pong.c.width - half){
          item.x = pong.c.width - half;
          item.drift = -Math.abs(item.drift) * 0.7;
        }
      }

      if(item.y - item.h * 0.6 > pong.c.height + 12 || item.x < -item.w * 0.9 || item.x > pong.c.width + item.w * 0.9){
        pong.madnessObjects.splice(i,1);
        continue;
      }

      if(collisionsEnabled && pongObstacleCollision(item)){
        bouncePongBallFromMovingObject(item, now);
      }
    }
  }
}

function drawPongMadness(ctx){
  if(!pongBalloonMadness) return;

  for(const item of pong.madnessObjects){
    if(!item.image || !item.image.complete || !item.image.naturalWidth) continue;
    ctx.save();
    if(item.flipX){
      ctx.translate(item.x, item.y);
      ctx.scale(-1, 1);
      ctx.drawImage(item.image, -item.w / 2, -item.h / 2, item.w, item.h);
    }else{
      ctx.drawImage(item.image, item.x - item.w / 2, item.y - item.h / 2, item.w, item.h);
    }
    ctx.restore();
  }
}

function loopPong(timestamp){
  if(view!=="pong" || !pong) return;
  const now = Number.isFinite(timestamp) ? timestamp : performance.now();
  const {c,ctx,ball}=pong;
  if(window.PongExtras?.isPaused()){
    pong.lastFrameAt=now;
    pongRAF=requestAnimationFrame(loopPong);
    return;
  }
  const dt = Math.min(0.05, Math.max(0, (now - pong.lastFrameAt) / 1000 || 0));
  pong.lastFrameAt = now;
  window.PongExtras?.tick(now,dt);
  const frameScale=window.PongExtras?.timeScale?.() ?? 1;
  pong.simulationNow=(Number.isFinite(pong.simulationNow)?pong.simulationNow:now)+dt*frameScale*1000;
  const gameNow=pong.simulationNow;

  if(!pong.over){
    if(pong.waitingForStart){
      // Mobile enters with the ball parked in the center. Press New to begin.
    } else if(pong.startCountdownUntil){
      const countdown = document.getElementById("pongLandscapeCountdown");
      if(countdown){ countdown.hidden=false; countdown.textContent=String(Math.max(1,Math.ceil((pong.startCountdownUntil-gameNow)/1000))); }
      if(gameNow >= pong.startCountdownUntil){
        pong.startCountdownUntil=0;
        document.body.classList.remove("pong-countdown");
        if(countdown) countdown.hidden=true;
        resetBall(Math.random() < 0.5 ? -1 : 1);
        window.MinikAudio?.play("game_start","pong-start");
      }
    } else if(pong.pointPauseUntil){
      if(gameNow >= pong.pointPauseUntil){
        finishPongPointPause();
      }
    } else {
      const previousBallPosition = {x:ball.x, y:ball.y};
      ball.x+=ball.vx*frameScale; ball.y+=ball.vy*frameScale;
      window.PongExtras?.collideTrain(previousBallPosition, gameNow);
      const settings = pongDifficultySettings[pongDifficulty];
      pong.aiReactionCounter -= frameScale;

      if(pong.pcVertical){
        const bounds=getPongCourtBounds();
        if(ball.x-ball.r<bounds.min){ ball.x=bounds.min+ball.r; ball.vx=Math.abs(ball.vx); }
        else if(ball.x+ball.r>bounds.max){ ball.x=bounds.max-ball.r; ball.vx=-Math.abs(ball.vx); }

        if(pong.aiReactionCounter <= 0){
          pong.aiReactionCounter = settings.reactionFrames;
          let target = ball.x;
          if(pong.aiForcedMiss && ball.vy < 0) target += pong.aiMissDirection * settings.missOffset;
          pong.aiTargetY = clampPongPaddle(target-pong.paddleHeight/2)+pong.paddleHeight/2;
        }
        const aiCenter=pong.aiY+pong.paddleHeight/2;
        const aiSpeed=pong.aiSlowRally ? settings.slowSpeed : settings.aiSpeed;
        pong.aiY += Math.sign(pong.aiTargetY-aiCenter) * Math.min(aiSpeed*frameScale,Math.abs(pong.aiTargetY-aiCenter));
        pong.aiY=clampPongPaddle(pong.aiY);

        if(ball.y+ball.r>c.height-30 && ball.y<c.height-16 && ball.x>pong.userY && ball.x<pong.userY+pong.paddleHeight && ball.vy>0){
          ball.vy=-Math.abs(ball.vy)*1.025;
          ball.vx+=(ball.x-(pong.userY+pong.paddleHeight/2))/24;
          pong.rallyHitCount+=1; releaseFlatRally(); recordPongPaddleContact("user",gameNow);
        }
        if(ball.y-ball.r<30 && ball.y>16 && ball.x>pong.aiY && ball.x<pong.aiY+pong.paddleHeight && ball.vy<0){
          ball.vy=Math.abs(ball.vy)*1.025;
          ball.vx+=(ball.x-(pong.aiY+pong.paddleHeight/2))/24;
          pong.rallyHitCount+=1; releaseFlatRally(); recordPongPaddleContact("ai",gameNow);
        }
        if(ball.y<0) awardPongPoint("user",1,gameNow);
        else if(ball.y>c.height) awardPongPoint("ai",-1,gameNow);
      }else{
        if(ball.y-ball.r<0){ ball.y=ball.r; ball.vy=Math.abs(ball.vy); }
        else if(ball.y+ball.r>c.height){ ball.y=c.height-ball.r; ball.vy=-Math.abs(ball.vy); }

        if(pong.aiReactionCounter <= 0){
          pong.aiReactionCounter = settings.reactionFrames;
          let target = ball.y;
          if(pong.aiForcedMiss && ball.vx > 0) target += pong.aiMissDirection * settings.missOffset;
          pong.aiTargetY = Math.max(pong.paddleHeight/2, Math.min(c.height-pong.paddleHeight/2,target));
        }
        const aiCenter=pong.aiY+pong.paddleHeight/2;
        const aiSpeed=pong.aiSlowRally ? settings.slowSpeed : settings.aiSpeed;
        pong.aiY += Math.sign(pong.aiTargetY-aiCenter) * Math.min(aiSpeed*frameScale,Math.abs(pong.aiTargetY-aiCenter));
        pong.aiY=Math.max(0,Math.min(c.height-pong.paddleHeight,pong.aiY));

        if(ball.x-ball.r<30 && ball.x>16 && ball.y>pong.userY && ball.y<pong.userY+pong.paddleHeight && ball.vx<0){
          ball.vx=Math.abs(ball.vx)*1.025;
          ball.vy+=(ball.y-(pong.userY+pong.paddleHeight/2))/24;
          pong.rallyHitCount+=1; releaseFlatRally(); recordPongPaddleContact("user",gameNow);
        }
        if(ball.x+ball.r>c.width-30 && ball.x<c.width-16 && ball.y>pong.aiY && ball.y<pong.aiY+pong.paddleHeight && ball.vx>0){
          ball.vx=-Math.abs(ball.vx)*1.025;
          ball.vy+=(ball.y-(pong.aiY+pong.paddleHeight/2))/24;
          pong.rallyHitCount+=1; releaseFlatRally(); recordPongPaddleContact("ai",gameNow);
        }
        if(ball.x<0) awardPongPoint("ai",1,gameNow);
        else if(ball.x>c.width) awardPongPoint("user",-1,gameNow);
      }
    }
  }

  updatePongMadness(gameNow,dt*frameScale);

  ctx.clearRect(0,0,c.width,c.height);
  ctx.setLineDash([10,14]);
  ctx.strokeStyle="rgba(69,65,120,.24)";
  ctx.lineWidth=3;
  ctx.beginPath();
  if(pong.pcVertical){
    const bounds=getPongCourtBounds();
    ctx.moveTo(bounds.min+20,c.height/2); ctx.lineTo(bounds.max-20,c.height/2);
  }else{
    ctx.moveTo(c.width/2,20); ctx.lineTo(c.width/2,c.height-20);
  }
  ctx.stroke();
  ctx.setLineDash([]);

  const pointActive = !!pong.pointPauseUntil && gameNow < pong.pointPauseUntil;
  const pointElapsed = pointActive ? gameNow - pong.pointPauseStartedAt : 0;
  const pulse = pointActive ? 0.5 + 0.5 * Math.sin(pointElapsed / 75) : 0;

  if(pong.pcVertical){
    drawPongPaddle(ctx,pong.userY,c.height-16-PONG_PADDLE_WIDTH,pong.paddleHeight,PONG_PADDLE_WIDTH,pong.palette.user,pointActive && pong.pointScorer === "user",pulse,window.PongExtras?.paddleRank?.() ?? -1);
    drawPongPaddle(ctx,pong.aiY,16,pong.paddleHeight,PONG_PADDLE_WIDTH,pong.palette.ai,pointActive && pong.pointScorer === "ai",pulse);
  }else{
    drawPongPaddle(ctx,16,pong.userY,PONG_PADDLE_WIDTH,pong.paddleHeight,pong.palette.user,pointActive && pong.pointScorer === "user",pulse,window.PongExtras?.paddleRank?.() ?? -1);
    drawPongPaddle(ctx,c.width-16-PONG_PADDLE_WIDTH,pong.aiY,PONG_PADDLE_WIDTH,pong.paddleHeight,pong.palette.ai,pointActive && pong.pointScorer === "ai",pulse);
  }

  const scorerColor = pong.pointScorer === "user" ? pong.palette.user : pong.palette.ai;
  const flashStep = Math.floor(pointElapsed / PONG_POINT_FLASH_STEP_MS);
  const chaosActive = gameNow < pong.ballChaosUntil;
  const chaosHue = Math.floor((gameNow / 3.8) % 360);
  const ballFill = chaosActive
    ? `hsl(${chaosHue} 95% 64%)`
    : (pointActive && flashStep % 2 === 0 ? scorerColor : "#fff");
  const ballGlow = chaosActive
    ? `hsl(${(chaosHue + 35) % 360} 100% 65%)`
    : (pointActive ? scorerColor : "#9f92ff");

  ctx.save();
  ctx.shadowColor=ballGlow;
  ctx.shadowBlur=chaosActive ? 26 : (pointActive ? 24 : 18);
  ctx.fillStyle=ballFill;
  ctx.strokeStyle="rgba(45,42,88,.38)";
  ctx.lineWidth=3;
  ctx.beginPath();
  ctx.arc(ball.x,ball.y,ball.r,0,Math.PI*2);
  ctx.fill();
  ctx.stroke();
  ctx.restore();

  drawPongMadness(ctx);

  pongRAF=requestAnimationFrame(loopPong);
}

function updatePongScore(){
  if(!pong) return;
  // Update every presentation from the same game state; explicit LTR digit order
  // keeps You/Minik aligned correctly even when the surrounding interface is RTL.
  document.querySelectorAll('[data-pong-score="user"], #userScore').forEach(score=>{
    score.textContent = pong.userScore;
  });
  document.querySelectorAll('[data-pong-score="ai"], #aiScore').forEach(score=>{
    score.textContent = pong.aiScore;
  });
}

function resizePongForViewport(){
  if(view!=="pong" || !pong || !pong.c) return;
  const c=pong.c; const rect=c.getBoundingClientRect();
  const mobile = isPongMobileDevice();
  const newWidth=Math.max(1,Math.round(rect.width));
  const newHeight=Math.max(1,Math.round(rect.height));
  if(Math.abs(newWidth-c.width)<2 && Math.abs(newHeight-c.height)<2){refreshPongCourtBounds();return;}
  const oldWidth=Math.max(1,c.width), oldHeight=Math.max(1,c.height);
  const oldPaddleHeight=pong.paddleHeight || PONG_PADDLE_HEIGHT;
  const oldAxis=pong.pcVertical ? oldWidth : oldHeight;
  const newAxis=pong.pcVertical ? newWidth : newHeight;
  const userCenterRatio=(pong.userY+oldPaddleHeight/2)/oldAxis;
  const aiCenterRatio=(pong.aiY+oldPaddleHeight/2)/oldAxis;
  const ballXRatio=pong.ball.x/oldWidth, ballYRatio=pong.ball.y/oldHeight;
  c.width=newWidth; c.height=newHeight;
  pong.paddleHeight=resolvedPongPaddleHeight(c);
  pong.userY=Math.max(0,Math.min(newAxis-pong.paddleHeight,userCenterRatio*newAxis-pong.paddleHeight/2));
  pong.aiY=Math.max(0,Math.min(newAxis-pong.paddleHeight,aiCenterRatio*newAxis-pong.paddleHeight/2));
  pong.aiTargetY=pong.aiY+pong.paddleHeight/2;
  pong.ball.x=Math.max(pong.ball.r,Math.min(newWidth-pong.ball.r,ballXRatio*newWidth));
  pong.ball.y=Math.max(pong.ball.r,Math.min(newHeight-pong.ball.r,ballYRatio*newHeight));
  refreshPongCourtBounds();
  if(pongBalloonMadness){
    pong.madnessObjects=[]; const now=performance.now();
    pong.nextBalloonSpawnAt=now+pongRandom(500,1000);
    pong.nextMiscSpawnAt=Math.max(now+1800,pong.madnessActivatedAt+PONG_MADNESS_EXTRA_DELAY_MS);
  }
}
let pongResizeTimer=null;
let lastPongLandscapeMode=false;
function handlePongViewportChange(){
  if(view!=="pong") return;
  // Apply layout classes now; debounce only the game-buffer rebuild.
  syncPongLandscapeClass();
  clearTimeout(pongResizeTimer);
  pongResizeTimer=setTimeout(()=>{
    if(view!=="pong") return;
    const landscapeNow = isPongMobileLandscape();
    syncPongLandscapeClass();

    // A fullscreen ad can temporarily rotate the Activity. Keep the completed
    // match (and its pending result callback) while adapting only its layout.
    if(pong && pong.over){
      lastPongLandscapeMode = landscapeNow;
      requestAnimationFrame(()=>requestAnimationFrame(resizePongForViewport));
      syncPongHeaderState();
      return;
    }

    if(landscapeNow !== lastPongLandscapeMode){
      lastPongLandscapeMode = landscapeNow;
      // Orientation changes always enter a parked/setup state rather than stretching an active rally.
      pongMobileStartRequested = false;
      pongLandscapeCountdownRequested = false;
      renderPong();
      return;
    }

    requestAnimationFrame(()=>requestAnimationFrame(resizePongForViewport));
  },120);
}

function schedulePongOrientationChecks(){
  [80, 220, 450, 800].forEach(delay=>{
    setTimeout(handlePongViewportChange, delay);
  });
}

window.addEventListener("resize",handlePongViewportChange);
window.addEventListener("orientationchange",schedulePongOrientationChecks);
if(window.visualViewport){
  window.visualViewport.addEventListener("resize",handlePongViewportChange);
}
if(screen.orientation && screen.orientation.addEventListener){
  screen.orientation.addEventListener("change",schedulePongOrientationChecks);
}

function drawPongPaddle(ctx,x,y,w,h,fill,isScorer,pulse,rank=-1){
  ctx.save();
  if(isScorer){
    ctx.shadowColor=fill;
    ctx.shadowBlur=12 + pulse * 16;
  }
  roundRect(ctx,x,y,w,h,9,fill);
  if(rank>=4){ctx.lineWidth=2;ctx.strokeStyle="#efc75e";ctx.beginPath();ctx.roundRect(x+1,y+1,w-2,h-2,8);ctx.stroke();}
  ctx.restore();
}

function roundRect(ctx,x,y,w,h,r,fill){
  ctx.beginPath();ctx.roundRect(x,y,w,h,r);ctx.fillStyle=fill;ctx.fill();
}

setLang(lang);
go("pong");

// Native monetization activity clock: train questions are not completed matches.
window.MinikMonetization.track(()=>view==="pong" && !!pong && !pong.over && !pong.waitingForStart && !pong.startCountdownUntil && !window.PongExtras?.isPaused());
