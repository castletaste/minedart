#!/usr/bin/env node
// Serves a Flutter web build, drives it in headless Chromium (SwiftShader
// WebGL2 + WebGPU), and prints the app's telemetry lines plus GPU buffer
// lifetime counters.
//
//   node tool/run_probe.mjs <build/web dir> [--seconds=60] [--query=?a=b]
//       [--prefix=S7 ] [--shot=out.png] [--viewport=1280x800] [--keys=F,F]
//       [--click=x,y] [--json=out.json] [--warm=20]
//
// Environment: PROBE_PW_DIR (node_modules/playwright, default ~/.cache/s7-chrome/pw),
// PROBE_CHROME (default ~/.cache/s7-chrome/chrome).
//
// SwiftShader rasterizes on the CPU, so absolute frame times are not device
// numbers. Compare engines only against each other on the same machine.
import { createRequire } from 'node:module';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';

const args = Object.fromEntries(
  process.argv.slice(3).map((a) => {
    const [k, ...v] = a.replace(/^--/, '').split('=');
    return [k, v.join('=') || 'true'];
  }),
);
const root = path.resolve(process.argv[2] || 'build/web');
const seconds = Number(args.seconds || 60);
const prefix = args.prefix ?? 'S7 ';
const [vw, vh] = (args.viewport || '1280x800').split('x').map(Number);
const require = createRequire(path.join(process.env.PROBE_PW_DIR || path.join(process.env.HOME, '.cache/s7-chrome/pw'), 'package.json'));
const { chromium } = require('playwright');

const types = {
  '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png',
  '.otf': 'font/otf', '.ttf': 'font/ttf', '.bin': 'application/octet-stream',
};
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  let file = path.join(root, decodeURIComponent(url.pathname));
  if (!file.startsWith(root)) { res.writeHead(403).end(); return; }
  if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
  if (!fs.existsSync(file)) { res.writeHead(404).end(); return; }
  res.writeHead(200, {
    'content-type': types[path.extname(file)] || 'application/octet-stream',
    // Production headers (Cloudflare _headers), so Wasm takes the same path.
    'cross-origin-embedder-policy': 'credentialless',
    'cross-origin-opener-policy': 'same-origin',
  });
  fs.createReadStream(file).pipe(res);
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const origin = `http://127.0.0.1:${server.address().port}`;

// Counts GPU buffer allocations and releases for both web backends.
const initScript = () => {
  globalThis.__rafFrames = 0;
  const tickRaf = () => { globalThis.__rafFrames++; requestAnimationFrame(tickRaf); };
  requestAnimationFrame(tickRaf);
  const c = (globalThis.__gpuCounters = {
    glCreate: 0, glDelete: 0, glBufferDataBytes: 0, glBufferSubDataBytes: 0,
    gpuCreate: 0, gpuDestroy: 0, gpuCreateBytes: 0, gpuWriteBytes: 0,
  });
  const wrap = (proto, name, fn) => {
    if (!proto || !proto[name]) return;
    const orig = proto[name];
    proto[name] = function (...a) { fn.apply(this, a); return orig.apply(this, a); };
  };
  const gl = globalThis.WebGL2RenderingContext?.prototype;
  wrap(gl, 'createBuffer', () => c.glCreate++);
  wrap(gl, 'deleteBuffer', () => c.glDelete++);
  wrap(gl, 'bufferData', (_t, d) => { c.glBufferDataBytes += typeof d === 'number' ? d : (d?.byteLength ?? 0); });
  wrap(gl, 'bufferSubData', (_t, _o, d, _so, len) => { c.glBufferSubDataBytes += len ?? d?.byteLength ?? 0; });
  wrap(globalThis.GPUDevice?.prototype, 'createBuffer', (d) => { c.gpuCreate++; c.gpuCreateBytes += d?.size ?? 0; });
  wrap(globalThis.GPUBuffer?.prototype, 'destroy', () => c.gpuDestroy++);
  wrap(globalThis.GPUQueue?.prototype, 'writeBuffer', (_b, _o, d, _do, size) => { c.gpuWriteBytes += size ?? d?.byteLength ?? 0; });
};

const flags = [
  '--enable-unsafe-webgpu', '--use-vulkan=swiftshader', '--use-angle=swiftshader',
  '--use-webgpu-adapter=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist',
  '--enable-features=Vulkan',
];
const browser = await chromium.launch({
  executablePath: process.env.PROBE_CHROME || path.join(process.env.HOME, '.cache/s7-chrome/chrome'),
  args: flags,
});
const page = await browser.newPage({ viewport: { width: vw, height: vh }, deviceScaleFactor: 1 });
await page.addInitScript(initScript);
const lines = [];
const errors = [];
const started = Date.now();
page.on('console', (m) => {
  const text = m.text();
  if (text.startsWith(prefix)) {
    const body = text.slice(prefix.length);
    let parsed;
    try { parsed = JSON.parse(body); } catch { parsed = { raw: body }; }
    parsed.t = ((Date.now() - started) / 1000).toFixed(1);
    lines.push(parsed);
    console.log(prefix + JSON.stringify(parsed));
  } else if (m.type() === 'error' || /error|exception/i.test(text)) {
    errors.push(text.slice(0, 400));
  }
});
page.on('pageerror', (e) => errors.push(`pageerror: ${String(e).slice(0, 400)}`));

const cdp = await page.context().newCDPSession(page);
await cdp.send('Performance.enable');
const sample = async () => {
  const { metrics } = await cdp.send('Performance.getMetrics');
  const m = Object.fromEntries(metrics.map((x) => [x.name, x.value]));
  return { task: m.TaskDuration, script: m.ScriptDuration, layout: m.LayoutDuration,
    frames: await page.evaluate(() => globalThis.__rafFrames), at: Date.now() };
};
const windows = [];
let windowStart = null;
await page.goto(origin + '/' + (args.query || ''), { waitUntil: 'load', timeout: 120000 });
const deadline = Date.now() + seconds * 1000;
let keysSent = false;
let clicked = false;
while (Date.now() < deadline) {
  await page.waitForTimeout(1000);
  const warm = Number(args.warm || 20);
  if (!windowStart && Date.now() - started > warm * 1000 && lines.length > 0) windowStart = await sample();
  const ready = lines.length > 0;
  if (ready && !keysSent && args.keys) {
    keysSent = true;
    await page.mouse.click(vw / 2, vh / 2);
    for (const key of args.keys.split(',')) {
      await page.keyboard.press(key);
      await page.waitForTimeout(300);
    }
  }
  if (ready && !clicked && args.click && Date.now() > deadline - seconds * 500) {
    clicked = true;
    const [x, y] = args.click.split(',').map(Number);
    await page.mouse.click(x, y);
  }
}
let mainThread = null;
if (windowStart) {
  const end = await sample();
  const frames = end.frames - windowStart.frames;
  const secs = (end.at - windowStart.at) / 1000;
  mainThread = { seconds: +secs.toFixed(1), frames, fps: +(frames / secs).toFixed(2),
    taskMsPerFrame: +((end.task - windowStart.task) * 1000 / frames).toFixed(2),
    scriptMsPerFrame: +((end.script - windowStart.script) * 1000 / frames).toFixed(2),
    busyFraction: +((end.task - windowStart.task) / secs).toFixed(3) };
}
if (args.shot) await page.screenshot({ path: args.shot });
const counters = await page.evaluate(() => globalThis.__gpuCounters);
const heap = await page.evaluate(() => performance.memory
  ? { usedJSHeapMB: +(performance.memory.usedJSHeapSize / 1048576).toFixed(1) }
  : null);
const result = { origin, seconds, mainThread, counters, heap, errors: errors.slice(0, 20), lines };
console.log('RESULT ' + JSON.stringify({ mainThread, counters, heap, errors: errors.slice(0, 20) }));
if (args.json) fs.writeFileSync(args.json, JSON.stringify(result, null, 2));
await browser.close();
server.close();
