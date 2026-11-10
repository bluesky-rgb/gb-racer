// Headless browser test of the web front end: layout, crisp scaling, input, audio pipeline.
const { chromium, webkit, devices } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const root = process.argv[2] || 'build/site';
const outDir = process.argv[3] || 'build';
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.gb': 'application/octet-stream', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  const f = path.join(root, req.url === '/' ? 'index.html' : req.url.split('?')[0]);
  fs.readFile(f, (err, data) => {
    if (err) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': types[path.extname(f)] || 'application/octet-stream' }); res.end(data);
  });
});
(async () => {
  await new Promise((r) => server.listen(8765, r));
  const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
  const results = [];
  const configs = [
    ['ipad-portrait', { ...devices['iPad (gen 7)'] }],
    ['ipad-landscape', { ...devices['iPad (gen 7) landscape'] }],
    ['ipad-pro11-landscape', { ...devices['iPad Pro 11 landscape'] }],
    ['iphone-portrait', { ...devices['iPhone 13'] }],
    ['desktop', { viewport: { width: 1280, height: 800 }, deviceScaleFactor: 1 }],
  ];
  for (const [name, opts] of configs) {
    const context = await browser.newContext(opts);
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', (e) => errors.push(String(e)));
    page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
    await page.goto('http://localhost:8765/');
    await page.waitForSelector('#start:not([hidden])', { timeout: 10000 });
    const touch = !!opts.hasTouch;
    if (touch) await page.tap('#start'); else await page.click('#start');
    await page.waitForTimeout(1500);
    const info = await page.evaluate(() => {
      const c = document.getElementById('lcd').getBoundingClientRect();
      const dpr = window.devicePixelRatio;
      const vis = (id) => { const e = document.getElementById(id); const r = e.getBoundingClientRect(); return r.width > 0 && getComputedStyle(e).display !== 'none' && r.bottom <= innerHeight + 1 && r.right <= innerWidth + 1 && r.left >= -1; };
      return { w: innerWidth, h: innerHeight, dpr, canvasCss: [c.width, c.height], scale: (c.width * dpr) / 160, scaleY: (c.height * dpr) / 144,
        integer: Number.isInteger(Math.round(c.width * dpr * 1000) / 1000 / 160), state: window.gbDebug.state(),
        dpad: vis('dpad'), a: vis('key-a'), b: vis('key-b'), start: vis('key-start'), select: vis('key-select'),
        scroll: [document.documentElement.scrollWidth > innerWidth, document.documentElement.scrollHeight > innerHeight] };
    });
    // input checks
    let input = {};
    if (touch) {
      const pos = await page.evaluate(() => { const g = (id) => { const r = document.getElementById(id).getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2, r.width]; }; return { d: g('dpad'), a: g('key-a'), b: g('key-b'), st: g('key-start') }; });
      const cdp = await context.newCDPSession(page);
      const pt = (x, y, id) => ({ x, y, id, radiusX: 10, radiusY: 10, force: 1 });
      const mask = () => page.evaluate(() => { const c = (id, k) => document.getElementById(id).classList.contains(k); return { left: c('dpad', 'left'), right: c('dpad', 'right'), up: c('dpad', 'up'), down: c('dpad', 'down'), a: c('key-a', 'on'), b: c('key-b', 'on'), start: c('key-start', 'on') }; });
      const r = pos.d[2] / 2;
      // left thumb on d-pad left + right thumb on A (multi-touch)
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [pt(pos.d[0] - r * 0.7, pos.d[1], 1)] });
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [pt(pos.d[0] - r * 0.7, pos.d[1], 1), pt(pos.a[0], pos.a[1], 2)] });
      input.leftPlusA = await mask();
      // slide the left thumb to the right side of the pad, slide the right thumb from A to B
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [pt(pos.d[0] + r * 0.7, pos.d[1], 1), pt(pos.b[0], pos.b[1], 2)] });
      input.slideRightPlusB = await mask();
      // diagonal
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [pt(pos.d[0] + r * 0.6, pos.d[1] - r * 0.6, 1), pt(pos.b[0], pos.b[1], 2)] });
      input.diagonal = await mask();
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
      input.released = await mask();
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [pt(pos.st[0], pos.st[1], 3)] });
      input.start = (await mask()).start;
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    } else {
      await page.keyboard.down('ArrowLeft'); await page.keyboard.down('KeyX');
      await page.waitForTimeout(100);
      input.keysHeld = 'ok';
      await page.keyboard.up('ArrowLeft'); await page.keyboard.up('KeyX');
    }
    await page.waitForTimeout(500);
    const state2 = await page.evaluate(() => window.gbDebug.state());
    await page.screenshot({ path: `${outDir}/web-${name}.png` });
    // swap cartridges: same emulator, other game
    const before = await page.evaluate(() => Array.from(document.getElementById('lcd').getContext('2d').getImageData(0, 0, 160, 144).data.filter((_, i) => i % 4 === 0)).join(','));
    if (touch) await page.tap('.cart[data-cart="lance"]'); else await page.click('.cart[data-cart="lance"]');
    await page.waitForTimeout(1500);
    const swap = await page.evaluate(() => ({
      state: window.gbDebug.state(), title: document.querySelector('.wordmark').textContent,
      a: document.getElementById('label-a').textContent, checked: document.querySelector('.cart[aria-checked="true"]').dataset.cart,
      url: location.search,
    }));
    const after = await page.evaluate(() => Array.from(document.getElementById('lcd').getContext('2d').getImageData(0, 0, 160, 144).data.filter((_, i) => i % 4 === 0)).join(','));
    swap.screenChanged = before !== after;
    await page.screenshot({ path: `${outDir}/web-${name}-lance.png` });
    results.push({ name, info, input, state2, swap, errors });
    await context.close();
  }
  console.log(JSON.stringify(results, null, 1));
  await browser.close();
  server.close();
})();
