/* MINIK v43 — shared sound effects for the website and bundled WebViews.
 * The bank contains the user's original MP3 bytes, not synthesized replacements.
 * Decoding a local bank avoids file:// fetch/CORS changes in Android and iOS.
 * Sounds never delay the game or queue behind other game events.
 */
(() => {
  "use strict";
  if (window.MinikAudio) return;
  const bank = window.MinikAudioBank || {};
  const CHANNELS = Object.freeze({
    "math-answer": { voices: 1, gain: 0.9 },
    "math-result": { voices: 1, gain: 0.9, replaces: ["math-answer"] },
    "pong-start": { voices: 1, gain: 0.85 },
    "pong-point": { voices: 1, gain: 0.85, replaces: ["pong-object", "pong-train"] },
    "pong-train": { voices: 1, gain: 0.85 },
    "pong-train-entry": { voices: 1, gain: 0.85 },
    "pong-object": { voices: 1, gain: 0.65 },
    "pong-paddle": { voices: 2, gain: 0.8 },
    "preview": { voices: 1, gain: 0.9 }
  });
  const MAX_AGE_MS = 350; // Drop late/missed hits, never play them after a later screen.
  const MASTER_GAIN = 0.75;
  const buffers = new Map(), failures = new Set(), active = new Set();
  const pendingByChannel = new Map(), generationByChannel = new Map();
  let context = null, master = null, backend = "unavailable", activated = false;
  let sequence = 0, epoch = 0, pageHidden = document.hidden, preparing = null;
  let lastError = null;
  const mediaPools = new Map();

  function stopVoice(voice) {
    if (!active.delete(voice)) return;
    try {
      if (voice.source) {
        voice.source.onended = null;
        voice.source.stop();
        voice.source.disconnect();
        voice.gain.disconnect();
      } else if (voice.media) {
        voice.media.pause();
        voice.media.currentTime = 0;
      }
    } catch (_) { /* Already ended or media is not seekable yet. */ }
  }
  function stop(channel) {
    generationByChannel.set(channel, (generationByChannel.get(channel) || 0) + 1);
    pendingByChannel.delete(channel);
    for (const voice of [...active]) if (voice.channel === channel) stopVoice(voice);
  }
  function stopAll() {
    epoch++;
    pendingByChannel.clear();
    for (const voice of [...active]) stopVoice(voice);
  }
  function valid(request) {
    return activated && !pageHidden && !document.hidden && request.epoch === epoch &&
      request.generation === (generationByChannel.get(request.channel) || 0) &&
      performance.now() - request.at <= MAX_AGE_MS;
  }
  function bytesFromBase64(value) {
    const binary = atob(value), bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes.buffer;
  }
  function decode(name) {
    return new Promise(resolve => {
      let done = false;
      const success = buffer => { if (done) return; done = true; buffers.set(name, buffer); resolve(); };
      const failure = () => { if (done) return; done = true; failures.add(name); resolve(); };
      try {
        // Both callback and Promise forms are handled; settle exactly once.
        const result = context.decodeAudioData(bytesFromBase64(bank[name]), success, failure);
        if (result && typeof result.then === "function") result.then(success, failure);
      } catch (_) { failure(); }
    });
  }
  function start(request) {
    if (!valid(request)) return false;
    const config = CHANNELS[request.channel];
    const peers = [...active].filter(v => v.channel === request.channel);
    while (peers.length >= config.voices) stopVoice(peers.shift());
    try {
      if (backend === "webaudio" && buffers.has(request.name) && context.state === "running") {
        const source = context.createBufferSource(), gain = context.createGain();
        source.buffer = buffers.get(request.name);
        gain.gain.value = config.gain;
        source.connect(gain); gain.connect(master);
        const voice = { channel: request.channel, name: request.name, source, gain };
        source.onended = () => {
          if (!active.delete(voice)) return;
          try { source.disconnect(); gain.disconnect(); } catch (_) {}
        };
        active.add(voice);
        try { source.start(0); } catch (error) { stopVoice(voice); throw error; }
        return true;
      }
      if (backend === "media") return startMedia(request, config);
    } catch (error) { lastError = String(error?.name || "AudioError"); }
    return false;
  }
  function flush() {
    for (const [channel, request] of [...pendingByChannel]) {
      if (!valid(request)) { pendingByChannel.delete(channel); continue; }
      if (backend === "webaudio" && (context.state !== "running" ||
          (!buffers.has(request.name) && !failures.has(request.name)))) continue;
      pendingByChannel.delete(channel);
      start(request);
    }
  }
  function initMedia() {
    if (typeof Audio !== "function") return;
    backend = "media";
    // Fixed reusable pool; no unbounded media elements in the frame loop.
    for (const name of Object.keys(bank)) {
      const pool = [];
      for (let i = 0; i < 2; i++) {
        const media = new Audio("data:audio/mpeg;base64," + bank[name]);
        media.preload = "auto";
        media.setAttribute("playsinline", "");
        pool.push(media);
      }
      mediaPools.set(name, pool);
    }
  }
  function startMedia(request, config) {
    const pool = mediaPools.get(request.name);
    if (!pool) return false;
    const media = pool.find(item => ![...active].some(v => v.media === item)) || pool[0];
    for (const old of [...active]) if (old.media === media) stopVoice(old);
    media.muted = false; media.volume = MASTER_GAIN * config.gain;
    try { media.currentTime = 0; } catch (_) {}
    const voice = { channel: request.channel, name: request.name, media };
    media.onended = () => active.delete(voice);
    media.onerror = () => { failures.add(request.name); stopVoice(voice); };
    active.add(voice);
    try {
      const result = media.play();
      if (result && typeof result.catch === "function") result.catch(error => {
        lastError = String(error?.name || "PlaybackBlocked"); stopVoice(voice);
      });
    } catch (error) { lastError = String(error?.name || "PlaybackBlocked"); stopVoice(voice); return false; }
    return true;
  }
  function prepare() {
    if (preparing) return preparing;
    const Constructor = window.AudioContext || window.webkitAudioContext;
    try {
      if (!Constructor) throw new Error("WebAudioUnavailable");
      context = new Constructor(); master = context.createGain();
      master.gain.value = MASTER_GAIN;
      // Bound simultaneous effects without hard clipping.
      const limiter = context.createDynamicsCompressor();
      limiter.threshold.value = -3; limiter.knee.value = 0; limiter.ratio.value = 12;
      limiter.attack.value = 0.003; limiter.release.value = 0.12;
      master.connect(limiter); limiter.connect(context.destination);
      backend = "webaudio";
      context.addEventListener("statechange", () => {
        if (context.state === "running") flush();
      });
      preparing = Promise.all(Object.keys(bank).map(decode)).then(() => { flush(); return snapshot(); });
    } catch (_) {
      try { initMedia(); } catch (_) { backend = "unavailable"; }
      preparing = Promise.resolve(snapshot());
    }
    return preparing;
  }
  function unlock(event) {
    // No fake click / no sound until the user actually interacts with this document.
    if (pageHidden || document.hidden || (event && !event.isTrusted)) return;
    activated = true;
    prepare();
    if (backend === "webaudio") {
      if (context.state !== "running") {
        try {
          const result = context.resume();
          if (result && typeof result.then === "function") result.then(flush, error => {
            lastError = String(error?.name || "PlaybackBlocked");
          });
        } catch (_) { lastError = "PlaybackBlocked"; }
      } else flush();
    } else if (backend === "media" && event) {
      // Older media-only WebViews may grant playback per element, so prime the
      // same pool during the gesture. Never play an audible file while priming.
      for (const pool of mediaPools.values()) for (const media of pool) {
        if ([...active].some(v => v.media === media)) continue;
        try {
          media.muted = true;
          const result = media.play();
          media.pause();
          try { media.currentTime = 0; } catch (_) {}
          media.muted = false;
          result?.catch(() => {});
        } catch (_) { media.muted = false; }
      }
    }
  }
  function play(name, channel) {
    if (!Object.hasOwn(bank, name) || !Object.hasOwn(CHANNELS, channel) ||
        !activated || pageHidden || document.hidden) return false;
    const config = CHANNELS[channel];
    for (const replaced of config.replaces || []) stop(replaced);
    // Same-channel rapid events replace old sounds, never form a delayed queue.
    if (config.voices === 1) stop(channel);
    const request = { name, channel, id: ++sequence, epoch, at: performance.now(),
      generation: generationByChannel.get(channel) || 0 };
    if (backend === "media" || (backend === "webaudio" && buffers.has(name) && context.state === "running")) {
      return start(request);
    }
    if (failures.has(name) || backend === "unavailable") return false;
    pendingByChannel.set(channel, request);
    // Resume only an already user-activated context; blocked clips expire rather
    // than being replayed minutes later when the user next touches the screen.
    if (backend === "webaudio" && context.state !== "running") unlock();
    return true;
  }
  function snapshot() {
    return { backend, activated, state: context?.state || null,
      loaded: [...buffers.keys()], failed: [...failures], lastError,
      active: [...active].map(v => ({ name: v.name, channel: v.channel })),
      pending: [...pendingByChannel.values()].map(v => ({ name: v.name, channel: v.channel })) };
  }
  window.MinikAudio = Object.freeze({ play, stop, stopAll, ready: prepare, snapshot });
  for (const type of ["pointerdown", "pointerup", "touchend", "click", "keydown"])
    document.addEventListener(type, unlock, { capture: true, passive: true });
  document.addEventListener("visibilitychange", () => {
    pageHidden = document.hidden;
    if (pageHidden) { stopAll(); try { context?.suspend()?.catch(() => {}); } catch (_) {} }
    else if (activated) unlock();
  });
  window.addEventListener("pagehide", () => {
    pageHidden = true; stopAll();
    try { context?.suspend()?.catch(() => {}); } catch (_) {}
  });
  window.addEventListener("pageshow", () => { pageHidden = document.hidden; if (activated && !pageHidden) unlock(); });
  prepare(); // Decode only. Never starts audio during page load.
})();
