// Checks MotionShelf effects and writes their thumbnails.
// Usage: node tools/check-effects.mjs [folder-name-prefix]
//   e.g. `node tools/check-effects.mjs title-` only checks effects whose folder starts with "title-".
// For each effect: window.seek / window.setParams exist, no JS errors, the background is transparent,
// and the frame changes when params change. The default frame on a checkerboard is saved as thumb.png (480×270).
// Test settings come from the optional "check" field in effect.json:
//   "check": { "time": 1.5, "params": { "text": "Hello" } }
// Without it, the frame at 60% of the duration is used and one param is changed automatically.
// Needs Node 22+ (built-in WebSocket) and Google Chrome (set CHROME=/path/to/chrome to override).
import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
// MOTIONSHELF_EFFECTS: set by the app when the user chose another effects folder
const effectsDir = process.env.MOTIONSHELF_EFFECTS || path.join(root, 'effects');
const shotsDir = path.join(os.tmpdir(), 'motionshelf-shots');
const profile = path.join(os.tmpdir(), 'motionshelf-chrome');
const only = process.argv[2] || '';
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const PORT = 9334;

// A param value that differs from the default, for the "frame changes" test
function variantFor(manifest) {
  for (const p of manifest.params) {
    if (p.type === 'color') return { [p.key]: String(p.default).toUpperCase() === '#FF5A36' ? '#3D5AFE' : '#FF5A36' };
    if (p.type === 'text') return { [p.key]: String(p.default) + ' 2' };
    if (p.type === 'number') return { [p.key]: p.default === p.max ? p.min : p.max };
    if (p.type === 'select' && p.options?.length > 1) return { [p.key]: p.options.find(o => o !== p.default) };
  }
  return {};
}

const names = fs.readdirSync(effectsDir, { withFileTypes: true })
  .filter(d => d.isDirectory() && !d.name.startsWith('_') && !d.name.startsWith('.') && d.name.startsWith(only))
  .map(d => d.name).sort();
if (!names.length) { console.log(`No effects found in ${effectsDir}` + (only ? ` starting with "${only}"` : '')); process.exit(1); }

fs.mkdirSync(shotsDir, { recursive: true });
const chrome = spawn(CHROME, [
  '--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`,
  '--no-first-run', '--no-default-browser-check', '--hide-scrollbars', 'about:blank',
], { stdio: 'ignore' });

let failed = 0;
try {
  let page;
  for (let i = 0; i < 100 && !page; i++) {
    try { page = (await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json()).find(t => t.type === 'page'); } catch {}
    if (!page) await sleep(200);
  }
  if (!page) throw new Error(`Could not connect to Chrome (${CHROME})`);

  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  let nextId = 0;
  const pending = new Map();
  let jsErrors = [];
  ws.onmessage = e => {
    const msg = JSON.parse(e.data);
    if (msg.method === 'Runtime.exceptionThrown') jsErrors.push(msg.params.exceptionDetails.exception?.description ?? msg.params.exceptionDetails.text);
    const p = pending.get(msg.id);
    if (!p) return;
    pending.delete(msg.id);
    msg.error ? p.reject(new Error(msg.error.message)) : p.resolve(msg.result);
  };
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++nextId;
    pending.set(id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params }));
  });
  const evaluate = async expression => {
    const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description ?? r.exceptionDetails.text);
    return r.result.value;
  };
  const shot = async (file, scale = 1) => {
    const clip = { x: 0, y: 0, width: 1920, height: 1080, scale };
    const { data } = await send('Page.captureScreenshot', { format: 'png', clip });
    fs.writeFileSync(file, Buffer.from(data, 'base64'));
  };

  await send('Runtime.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false });

  let index = 0;
  for (const name of names) {
    const dir = path.join(effectsDir, name);
    const problems = [];
    jsErrors = [];
    let manifest;
    try { manifest = JSON.parse(fs.readFileSync(path.join(dir, 'effect.json'), 'utf8')); }
    catch (e) { failed++; console.log(`✗ ${name}: cannot read effect.json (${e.message})`); continue; }
    const defaults = Object.fromEntries(manifest.params.map(p => [p.key, p.default]));
    const time = manifest.check?.time ?? manifest.duration * .6;
    const variant = manifest.check?.params ?? variantFor(manifest);
    for (const key of Object.keys(variant)) if (!(key in defaults)) problems.push(`test param "${key}" is not in effect.json`);

    await send('Page.navigate', { url: 'file://' + path.join(dir, 'effect.html') });
    await sleep(400);
    const api = await evaluate(`typeof window.seek === 'function' && typeof window.setParams === 'function'`);
    if (!api) problems.push('window.seek or window.setParams is missing');

    // Same as the app: send the defaults, then seek
    await evaluate(`setParams(${JSON.stringify(defaults)}); seek(${time}); 0`);
    const isCanvas = await evaluate(`!!document.getElementById('c')`);
    // DOM effects: screenshot with a transparent background, then read the alpha back in the page
    const pageShot = async () => {
      await send('Emulation.setDefaultBackgroundColorOverride', { color: { r: 0, g: 0, b: 0, a: 0 } });
      const { data } = await send('Page.captureScreenshot', { format: 'png' });
      return 'data:image/png;base64,' + data;
    };
    const alphaOf = url => evaluate(`new Promise(res => { const img = new Image(); img.onload = () => {
      const c = document.createElement('canvas'); c.width = img.width; c.height = img.height;
      const g = c.getContext('2d'); g.drawImage(img, 0, 0);
      const d = g.getImageData(0, 0, c.width, c.height).data; let clear = 0, total = 0;
      for (let i = 3; i < d.length; i += 4 * 97) { total++; if (d[i] === 0) clear++; }
      res(clear / total); }; img.src = ${JSON.stringify(url)}; })`);
    const stats = isCanvas ? await evaluate(`(() => {
      const c = document.getElementById('c'), d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
      let clear = 0, total = 0;
      for (let i = 3; i < d.length; i += 4 * 97) { total++; if (d[i] === 0) clear++; }
      return { clear: clear / total, url: c.toDataURL() };
    })()`) : await (async () => { const url = await pageShot(); return { clear: await alphaOf(url), url }; })();
    if (stats.clear < .05) problems.push(`only ${(stats.clear * 100).toFixed(1)}% of the frame is transparent`);

    await evaluate(`document.body.style.background = 'repeating-conic-gradient(#3a3a3a 0 25%, #4d4d4d 0 50%) 0 0 / 40px 40px'; 0`);
    await shot(path.join(shotsDir, `${String(index++).padStart(2, '0')}.png`));
    await shot(path.join(dir, 'thumb.png'), .25);

    await evaluate(`setParams(${JSON.stringify(variant)}); 0`);
    await evaluate(`document.body.style.background = 'transparent'; 0`);
    const changed = (isCanvas ? await evaluate(`document.getElementById('c').toDataURL()`) : await pageShot()) !== stats.url;
    await evaluate(`document.body.style.background = 'repeating-conic-gradient(#3a3a3a 0 25%, #4d4d4d 0 50%) 0 0 / 40px 40px'; 0`);
    if (!changed && Object.keys(variant).length) problems.push('the frame did not change after changing params');
    await shot(path.join(shotsDir, `${String(index++).padStart(2, '0')}.png`));

    if (jsErrors.length) problems.push(`JS errors: ${jsErrors.join(' / ')}`);
    if (problems.length) failed++;
    console.log(`${problems.length ? '✗' : '✓'} ${name} (${(stats.clear * 100).toFixed(0)}% transparent)${problems.length ? ': ' + problems.join('; ') : ''}`);
  }
  ws.close();
} finally {
  chrome.kill();
}
process.exit(failed ? 1 : 0);
