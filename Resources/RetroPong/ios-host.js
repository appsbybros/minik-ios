/* iOS host boundary only. Game rules, drawing, scoring and timing remain in the Android payload. */
(() => {
  "use strict";
  const key = "minik.pong.progress.v1", config = window.__minikRetroConfig || {};
  const send = value => { try { window.webkit?.messageHandlers?.retroPong?.postMessage(value); } catch (_) {} };
  let active = config.paused !== true;
  const canExit = config.canExit === true;
  let exiting = false;
  document.documentElement.classList.toggle('minik-ios-standalone', !canExit);
  let memory = typeof config.state === "object" && config.state ? JSON.stringify(config.state) : null;
  // App Store captures only: the native -MinikScreenshotScene launch argument names
  // a screen. Its progress is staged in memory and never saved to the device.
  const scene = typeof window.MinikScreenshotScene === "string" ? window.MinikScreenshotScene : "";
  const sceneStates = {
    setup: {points: 240},
    help: {points: 340},
    play: {points: 240, trainMode: "off"},
    train: {points: 1280, levels: {addition: 12, subtraction: 1, multiply: 1, divide: 1}}
  };
  const staged = Object.prototype.hasOwnProperty.call(sceneStates, scene);
  if (staged) {
    memory = JSON.stringify(Object.assign({version: 1, operation: "addition", trainMode: "tap",
      levels: {addition: 1, subtraction: 1, multiply: 1, divide: 1}, controlTouch: "arrows",
      opponentDifficulty: "beginner", targetScore: 5}, sceneStates[scene]));
    window.addEventListener("load", () => setTimeout(() => {
      if (scene === "help") window.PongExtras?.openSettings(false);
      else if (scene === "play" || scene === "train") window.resetPong?.();
    }, 1200), {once: true});
  }
  // Mirror only the Pong key. Native UserDefaults survive WKWebView file-origin/installation changes.
  const originalGet = Storage.prototype.getItem, originalSet = Storage.prototype.setItem;
  if (memory && !staged) { try { originalSet.call(localStorage, key, memory); } catch (_) {} }
  Storage.prototype.getItem = function(name) {
    if (this === localStorage && name === key && memory != null) return memory;
    return originalGet.call(this, name);
  };
  Storage.prototype.setItem = function(name, value) {
    if (this === localStorage && name === key) {
      memory = String(value);
      if (staged) return;
      try { originalSet.call(this, name, memory); } catch (_) {} // Native mirror remains durable.
      send({type: "save", state: memory}); return;
    }
    return originalSet.call(this, name, value);
  };
  window.MinikRetroHost = Object.freeze({
    canExit,
    language: config.language === "he" ? "he" : config.language === "en" ? "en" : null,
    setActive(value) {
      active = value === true;
      window.PongExtras?.nativePause(!active);
      if (!active) window.MinikAudio?.stopAll();
    }
  });
  window.PongMusic = Object.freeze({start: () => send({type: "music", playing: true}), stop: () => send({type: "music", playing: false})});
  // Android Bounce's MinikMonetization contract (minik-monetization.js), answered by the native host:
  // the saved result shows after the host's ad boundary, and "For parents" opens the native gate.
  const monetization = config.monetization === true, parents = config.parents === true;
  const pendingResults = new Map();
  let resultSequence = 0, playing = () => false, menuRoot = null, idleTimer = 0;
  const showResult = token => {
    const callback = pendingResults.get(String(token));
    if (!callback) return;
    pendingResults.delete(String(token)); callback();
  };
  // Android Bounce (minik-monetization.js `menuIdle`): every second the setup with the "For parents"
  // link is idle on screen, the native host may show the family remove-ads reminder.
  const menuIdle = () => {
    if (!active || document.hidden || pendingResults.size || !menuRoot || !menuRoot.isConnected) return;
    let busy = true;
    try { busy = !!playing(); } catch (_) {}
    if (busy || !menuRoot.getClientRects().length || getComputedStyle(menuRoot).visibility === "hidden") return;
    send({type: "menuIdle"});
  };
  window.MinikMonetization = Object.freeze({
    begin(kind) { return String(kind) + "/" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2); },
    finish(id, callback) {
      if (typeof callback !== "function") return;
      if (!monetization) { callback(); return; }
      window.MinikAudio?.stopAll();
      const token = String(++resultSequence);
      pendingResults.set(token, callback);
      send({type: "matchFinished", id: String(id || ""), token});
      setTimeout(() => showResult(token), 20000); // Never strand the result if the host does not answer.
    },
    complete(token) { showResult(token); },
    track(getter) { if (typeof getter === "function") playing = getter; },
    menu(parent, lang) {
      if (!parents || !parent) return null;
      menuRoot = parent;
      if (!idleTimer) idleTimer = setInterval(menuIdle, 1000);
      const button = document.createElement("button");
      button.type = "button"; button.className = "minik-parent-entry";
      button.textContent = lang === "he" ? "להורים" : "For parents";
      button.setAttribute("aria-label", lang === "he" ? "להורים · הסרת פרסומות" : "For parents · Remove ads");
      if (getComputedStyle(parent).position === "static") parent.style.position = "relative";
      Object.assign(button.style, {position: "absolute", bottom: "10px", insetInlineStart: "16px", zIndex: "2", padding: "10px 12px",
        minHeight: "44px", color: "#3F8CFF", background: "transparent", border: "0", font: "inherit", fontSize: "15px",
        fontWeight: "700", textDecoration: "underline", cursor: "pointer", whiteSpace: "nowrap"});
      button.onclick = () => send({type: "parents"});
      parent.append(button);
      // As on Android, never cover a setup control on unusual screens.
      const overlaps = () => {
        const r = button.getBoundingClientRect();
        return [...parent.querySelectorAll("button,h2,select")].some(other => {
          if (other === button) return false;
          const q = other.getBoundingClientRect();
          return q.width && r.left < q.right && r.right > q.left && r.top < q.bottom && r.bottom > q.top;
        });
      };
      requestAnimationFrame(() => {
        if (!button.isConnected || !overlaps()) return;
        button.style.bottom = "auto"; button.style.top = "10px"; button.style.insetInlineStart = "50%";
        button.style.transform = "translateX(" + (document.documentElement.dir === "rtl" ? "50%" : "-50%") + ")";
        if (overlaps()) button.style.display = "none";
      });
      return button;
    }
  });
  document.addEventListener("DOMContentLoaded", () => {
    // iOS does not quit itself. The standalone setup is its root; embedded games
    // return through the native callback. Neither route renders a dead-end page.
    window.exitPong = () => {
      if (exiting) return;
      window.stopPongSession?.();
      window.MinikAudio?.stopAll();
      window.PongMusic.stop();
      if (canExit) { exiting = true; send({type: "exit"}); }
      else window.returnToPongSetup?.();
    };
    window.MinikRetroHost.setActive(active);
  }, {once: true});
})();
