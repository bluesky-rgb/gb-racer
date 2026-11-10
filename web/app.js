/* Front end for the WebAssembly Game Boy core: video, audio, touch and keyboard input. */
(() => {
  'use strict';

  const KEY = { right: 1, left: 2, up: 4, down: 8, a: 16, b: 32, select: 64, start: 128 };
  const GB_FPS = 4194304 / 70224;           // 59.7275 frames per second
  const FRAME_MS = 1000 / GB_FPS;
  const ROM_URL = 'racer.gb';

  const PALETTES = {
    green: { label: 'Green screen', colors: [0xe0ecb4, 0x9db86a, 0x4d6e3c, 0x182a1c] },
    gray: { label: 'Gray screen', colors: [0xf4f4ee, 0xa6a8a2, 0x54575a, 0x111315] },
  };

  const $ = (id) => document.getElementById(id);
  const canvas = $('lcd');
  const ctx2d = canvas.getContext('2d', { alpha: false });
  const image = ctx2d.createImageData(160, 144);
  const startBtn = $('start');
  const note = $('note');

  let wasm = null;          // exports
  let romLoaded = false;
  let running = false;      // emulation loop active
  let userPaused = false;
  let soundOn = true;
  let paletteName = 'green';
  try { paletteName = localStorage.getItem('lcd') || 'green'; } catch (e) { /* private mode */ }
  if (!PALETTES[paletteName]) paletteName = 'green';

  /* ------------------------------------------------------------------ video */

  function applyPalette() {
    const p = PALETTES[paletteName];
    $('btn-lcd').textContent = p.label;
    canvas.style.background = '#' + p.colors[0].toString(16).padStart(6, '0');
    if (!wasm) return;
    p.colors.forEach((rgb, i) => {
      const r = (rgb >> 16) & 255, g = (rgb >> 8) & 255, b = rgb & 255;
      wasm.wasm_set_palette(i, (0xff000000 | (b << 16) | (g << 8) | r) >>> 0);   // little-endian RGBA
    });
  }

  function present() {
    const src = new Uint8ClampedArray(wasm.memory.buffer, wasm.wasm_video(), 160 * 144 * 4);
    image.data.set(src);
    ctx2d.putImageData(image, 0, 0);
  }

  function blankScreen() {
    const c = PALETTES[paletteName].colors[0];
    ctx2d.fillStyle = '#' + c.toString(16).padStart(6, '0');
    ctx2d.fillRect(0, 0, 160, 144);
  }

  /* Size the canvas to a whole multiple of 160x144 in *device* pixels so every
   * Game Boy pixel covers the same number of screen pixels: crisp, no shimmer. */
  function layout() {
    const stage = $('stage');
    const bezel = $('bezel');
    const dpr = window.devicePixelRatio || 1;
    const cs = getComputedStyle(bezel);
    const padX = parseFloat(cs.paddingLeft) + parseFloat(cs.paddingRight);
    const padY = parseFloat(cs.paddingTop) + parseFloat(cs.paddingBottom);
    const rumble = document.querySelector('.rumble').offsetHeight;
    const availW = (stage.clientWidth - padX) * dpr;
    const availH = (stage.clientHeight - padY - rumble - 4) * dpr;
    const k = Math.max(1, Math.floor(Math.min(availW / 160, availH / 144)));
    canvas.style.width = (160 * k) / dpr + 'px';
    canvas.style.height = (144 * k) / dpr + 'px';
    measureControls();
  }

  /* ------------------------------------------------------------------ audio */

  let audioCtx = null, audioNode = null, audioGain = null;
  let audioFill = 0, audioTarget = 0, baseRate = 48000, currentRate = 0;

  async function initAudio() {
    if (audioCtx) { if (audioCtx.state !== 'running') audioCtx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    audioCtx = new AC({ latencyHint: 'interactive' });
    audioGain = audioCtx.createGain();
    audioGain.gain.value = soundOn ? 1 : 0;
    audioGain.connect(audioCtx.destination);
    audioTarget = Math.round(audioCtx.sampleRate * 0.07);     // ~70 ms of buffered sound
    try {
      await audioCtx.audioWorklet.addModule('audio-worklet.js');
      audioNode = new AudioWorkletNode(audioCtx, 'gb-audio', { numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [2], processorOptions: { target: audioTarget } });
      audioNode.port.onmessage = (e) => { audioFill = e.data.fill; };
      audioNode.connect(audioGain);
    } catch (err) {
      audioNode = scriptProcessorFallback();
    }
    audioCtx.resume();
    setRate();
  }

  /* older browsers without AudioWorklet */
  function scriptProcessorFallback() {
    const size = 32768, L = new Float32Array(size), R = new Float32Array(size);
    let rd = 0, wr = 0, count = 0, primed = false;
    const node = audioCtx.createScriptProcessor(1024, 0, 2);
    node.onaudioprocess = (e) => {
      const l = e.outputBuffer.getChannelData(0), r = e.outputBuffer.getChannelData(1);
      if (!primed && count >= audioTarget) primed = true;
      for (let i = 0; i < l.length; i++) {
        if (primed && count > 0) { l[i] = L[rd]; r[i] = R[rd]; rd = (rd + 1) % size; count--; }
        else { l[i] = 0; r[i] = 0; primed = false; }
      }
      audioFill = count;
    };
    node.port = { postMessage: (m) => {
      const s = m.samples;
      for (let i = 0; i < s.length; i += 2) {
        if (count >= size) { rd = (rd + 1) % size; count--; }
        L[wr] = s[i]; R[wr] = s[i + 1]; wr = (wr + 1) % size; count++;
      }
    } };
    node.connect(audioGain);
    return node;
  }

  /* The emulator makes sound at `rate` samples per emulated second. Nudge it by up to
   * 1% so the playback buffer hovers around its target instead of drifting. */
  function setRate() {
    if (!wasm || !audioCtx) return;
    const speed = lockedRefresh ? lockedRefresh / lockDivider / GB_FPS : 1;   // emulated seconds per real second
    baseRate = audioCtx.sampleRate / speed;
    let adj = 0;
    if (audioFill > 0) adj = Math.max(-0.01, Math.min(0.01, ((audioTarget - audioFill) / audioTarget) * 0.02));
    const rate = Math.round(baseRate * (1 + adj));
    if (rate !== currentRate) { currentRate = rate; wasm.wasm_set_rate(rate); }
  }

  function pushAudio(frames) {
    if (!audioNode || !frames || audioCtx.state !== 'running') return;
    const samples = new Float32Array(wasm.memory.buffer, wasm.wasm_audio(), frames * 2).slice();
    audioNode.port.postMessage({ samples }, [samples.buffer]);
  }

  /* ------------------------------------------------------------- main loop */

  let lastT = 0, acc = 0, rafId = 0;
  let lockedRefresh = 0, lockDivider = 1, tick = 0;
  const intervals = [];

  /* If the display refreshes at (a multiple of) ~60 Hz, run exactly one emulated frame
   * per refresh for perfectly even motion; otherwise fall back to a time accumulator. */
  function detectRefresh(dt) {
    intervals.push(dt);
    if (intervals.length < 40) return;
    const sorted = intervals.slice().sort((a, b) => a - b);
    const hz = 1000 / sorted[sorted.length >> 1];
    intervals.length = 0;
    let lock = 0, div = 1;
    for (const d of [1, 2]) if (Math.abs(hz / d - 60) < 2.5) { lock = hz; div = d; }
    if (lock) lockedRefresh = lockedRefresh ? lockedRefresh * 0.8 + lock * 0.2 : lock;
    else lockedRefresh = 0;
    lockDivider = div;
  }

  function runFrame() {
    wasm.wasm_set_keys(keyMask());
    pushAudio(wasm.wasm_run_frame());
  }

  function loop(t) {
    rafId = requestAnimationFrame(loop);
    const dt = t - lastT;
    lastT = t;
    if (dt <= 0 || dt > 250) { acc = 0; return; }       // tab was in the background
    detectRefresh(dt);
    tick++;
    let frames = 0;
    if (lockedRefresh) {
      if (tick % lockDivider === 0) frames = 1;
      acc = 0;
    } else {
      acc += dt;
      while (acc >= FRAME_MS && frames < 3) { acc -= FRAME_MS; frames++; }
      if (acc > FRAME_MS * 3) acc = 0;
    }
    for (let i = 0; i < frames; i++) runFrame();
    if (frames) { present(); setRate(); }
  }

  function setRunning(on) {
    if (on === running) return;
    running = on;
    cancelAnimationFrame(rafId);
    if (on) { lastT = performance.now(); acc = 0; intervals.length = 0; rafId = requestAnimationFrame(loop); }
    if (audioCtx) { if (on) audioCtx.resume(); else audioCtx.suspend(); }
  }

  /* ------------------------------------------------------------------ input */

  const held = new Set();          // keyboard
  let touchMask = 0;
  const keyMask = () => { let m = touchMask; for (const k of held) m |= k; return m; };

  const KEYMAP = {
    ArrowRight: KEY.right, ArrowLeft: KEY.left, ArrowUp: KEY.up, ArrowDown: KEY.down,
    KeyD: KEY.right, KeyA: KEY.left, KeyW: KEY.up, KeyS: KEY.down,
    KeyX: KEY.a, KeyK: KEY.a, Space: KEY.a, KeyZ: KEY.b, KeyJ: KEY.b,
    Enter: KEY.start, ShiftLeft: KEY.select, ShiftRight: KEY.select, Backspace: KEY.select,
  };
  window.addEventListener('keydown', (e) => {
    const k = KEYMAP[e.code];
    if (!k || e.metaKey || e.ctrlKey || e.altKey) return;
    if (document.activeElement && document.activeElement.classList.contains('tool') && (e.code === 'Enter' || e.code === 'Space')) return;
    e.preventDefault();
    if (!started) begin();
    held.add(k);
  });
  window.addEventListener('keyup', (e) => { const k = KEYMAP[e.code]; if (k) held.delete(k); });
  window.addEventListener('blur', () => held.clear());

  /* Touch: every active finger is re-evaluated on each event, so thumbs can slide
   * between directions and buttons without lifting. */
  let geo = null;
  function measureControls() {
    const r = (id) => $(id).getBoundingClientRect();
    const c = (rect) => ({ x: rect.left + rect.width / 2, y: rect.top + rect.height / 2, r: rect.width / 2 });
    geo = { dpad: c(r('dpad')), a: c(r('key-a')), b: c(r('key-b')), select: r('key-select'), start: r('key-start') };
  }

  const fingers = new Map();       // identifier -> zone
  function zoneOf(target) {
    const z = target.closest ? target.closest('.zone') : null;
    return z ? z.id : null;
  }

  function evaluate(touches) {
    let m = 0;
    for (const t of touches) {
      const zone = fingers.get(t.identifier);
      if (!zone) continue;
      const x = t.clientX, y = t.clientY;
      if (zone === 'zone-dpad') {
        const dx = x - geo.dpad.x, dy = y - geo.dpad.y;
        const dist = Math.hypot(dx, dy);
        if (dist > geo.dpad.r * 0.16) {
          // eight sectors; a direction is held when the finger is within 67.5 degrees of it
          const ang = Math.atan2(dy, dx), lim = Math.cos((67.5 * Math.PI) / 180);
          if (Math.cos(ang) > lim) m |= KEY.right;
          if (Math.cos(ang) < -lim) m |= KEY.left;
          if (Math.sin(ang) > lim) m |= KEY.down;
          if (Math.sin(ang) < -lim) m |= KEY.up;
        }
      } else if (zone === 'zone-ab') {
        const da = Math.hypot(x - geo.a.x, y - geo.a.y), db = Math.hypot(x - geo.b.x, y - geo.b.y);
        const reach = geo.a.r * 1.9;
        if (da < reach * 0.62 && db < reach * 0.62) m |= KEY.a | KEY.b;   // thumb across both
        else if (da <= db && da < reach) m |= KEY.a;
        else if (db < da && db < reach) m |= KEY.b;
      } else if (zone === 'zone-sys') {
        const mid = (geo.select.right + geo.start.left) / 2;
        m |= x < mid ? KEY.select : KEY.start;
      }
    }
    touchMask = m;
    const d = $('dpad').classList;
    d.toggle('up', !!(m & KEY.up)); d.toggle('down', !!(m & KEY.down));
    d.toggle('left', !!(m & KEY.left)); d.toggle('right', !!(m & KEY.right));
    $('key-a').classList.toggle('on', !!(m & KEY.a));
    $('key-b').classList.toggle('on', !!(m & KEY.b));
    $('key-select').classList.toggle('on', !!(m & KEY.select));
    $('key-start').classList.toggle('on', !!(m & KEY.start));
  }

  function onTouch(e) {
    document.body.classList.add('touch');
    let ours = false;                       // does this event involve a finger on the game controls?
    if (e.type === 'touchstart') {
      for (const t of e.changedTouches) {
        const z = zoneOf(t.target);
        if (z) { fingers.set(t.identifier, z); ours = true; }
      }
      if (ours && !started) begin();
    } else if (e.type === 'touchmove') {
      ours = fingers.size > 0;
    } else {
      for (const t of e.changedTouches) if (fingers.delete(t.identifier)) ours = true;
    }
    if (!ours) return;                      // toolbar buttons and the start button behave normally
    if (e.cancelable) e.preventDefault();
    if (!geo) measureControls();
    evaluate(e.touches);
  }
  for (const type of ['touchstart', 'touchmove', 'touchend', 'touchcancel'])
    document.addEventListener(type, onTouch, { passive: false });

  /* mouse on the on-screen controls (touch laptops, testing) */
  let mouseKey = 0;
  const mouseTargets = { 'key-a': KEY.a, 'key-b': KEY.b, 'key-select': KEY.select, 'key-start': KEY.start };
  document.addEventListener('mousedown', (e) => {
    const el = e.target.closest && e.target.closest('.round, .pill');
    if (el && mouseTargets[el.id]) { mouseKey = mouseTargets[el.id]; held.add(mouseKey); el.classList.add('on'); }
  });
  document.addEventListener('mouseup', () => {
    if (mouseKey) { held.delete(mouseKey); mouseKey = 0; document.querySelectorAll('.round.on, .pill.on').forEach((n) => n.classList.remove('on')); }
  });

  /* iOS: stop pinch and double-tap zoom, the long-press menu and rubber-band scrolling */
  for (const type of ['gesturestart', 'gesturechange', 'gestureend', 'contextmenu', 'dblclick'])
    document.addEventListener(type, (e) => e.preventDefault(), { passive: false });

  /* ---------------------------------------------------------------- controls */

  let started = false;
  function begin() {
    if (!romLoaded) return;
    started = true;
    startBtn.hidden = true;
    note.hidden = true;
    initAudio();
    if (!userPaused) setRunning(true);
  }
  startBtn.addEventListener('click', begin);

  $('btn-sound').addEventListener('click', () => {
    soundOn = !soundOn;
    $('btn-sound').setAttribute('aria-pressed', String(soundOn));
    if (audioGain) audioGain.gain.value = soundOn ? 1 : 0;
    if (soundOn && started) initAudio();
  });
  $('btn-pause').addEventListener('click', () => {
    if (!started) { begin(); return; }
    userPaused = !userPaused;
    $('btn-pause').setAttribute('aria-pressed', String(userPaused));
    $('btn-pause').textContent = userPaused ? 'Resume' : 'Pause';
    setRunning(!userPaused);
  });
  $('btn-lcd').addEventListener('click', () => {
    paletteName = paletteName === 'green' ? 'gray' : 'green';
    try { localStorage.setItem('lcd', paletteName); } catch (e) { /* ignore */ }
    applyPalette();
    if (romLoaded && started) { wasm.wasm_set_keys(0); if (!running) present(); }
  });

  const root = document.documentElement;
  const canFull = root.requestFullscreen || root.webkitRequestFullscreen;
  if (canFull) {
    $('btn-full').hidden = false;
    $('btn-full').addEventListener('click', () => {
      const el = document.fullscreenElement || document.webkitFullscreenElement;
      if (el) (document.exitFullscreen || document.webkitExitFullscreen).call(document);
      else canFull.call(root);
    });
  }

  $('btn-rom').addEventListener('click', () => $('file').click());
  $('file').addEventListener('change', async (e) => {
    const f = e.target.files[0];
    if (!f) return;
    loadRom(new Uint8Array(await f.arrayBuffer()));
    document.querySelector('.wordmark').textContent = f.name.replace(/\.[^.]+$/, '');
    begin();
  });

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) setRunning(false);
    else if (started && !userPaused) setRunning(true);
  });
  window.addEventListener('resize', layout);
  window.addEventListener('orientationchange', () => setTimeout(layout, 250));

  /* ------------------------------------------------------------------- boot */

  function loadRom(bytes) {
    if (bytes.length > wasm.wasm_rom_max()) { showNote('That file is too large to be a Game Boy ROM.'); return; }
    new Uint8Array(wasm.memory.buffer, wasm.wasm_rom_buffer(), bytes.length).set(bytes);
    currentRate = 0;
    wasm.wasm_load(bytes.length, audioCtx ? audioCtx.sampleRate : 48000);
    applyPalette();
    setRate();
    romLoaded = true;
  }

  function showNote(text) { note.textContent = text; note.hidden = false; }

  async function boot() {
    applyPalette();
    blankScreen();
    layout();
    try {
      const [wasmRes, romRes] = await Promise.all([fetch('gb.wasm'), fetch(ROM_URL)]);
      if (!wasmRes.ok) throw new Error('gb.wasm');
      const { instance } = await WebAssembly.instantiate(await wasmRes.arrayBuffer(), {});
      wasm = instance.exports;
      if (romRes.ok) {
        loadRom(new Uint8Array(await romRes.arrayBuffer()));
        // draw the first frames behind the start button so the screen is not empty
        for (let i = 0; i < 4; i++) wasm.wasm_run_frame();
        wasm.wasm_reset();
        applyPalette();
        blankScreen();
        startBtn.textContent = matchMedia('(pointer: coarse)').matches ? 'Tap to play' : 'Click to play';
        startBtn.hidden = false;
      } else {
        showNote('No game is bundled with this page. Use “Open ROM” to choose a .gb file.');
      }
    } catch (err) {
      showNote('The emulator could not be loaded. Check your connection and reload the page.');
    }
    window.gbDebug = { wasm: () => wasm, state: () => ({ running, started, lockedRefresh, lockDivider, audioFill, audioTarget, currentRate, ctx: audioCtx && audioCtx.state }) };
  }
  boot();
})();
