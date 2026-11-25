// A canvas resized with the page (bun run test ui-web): WebTodo.wasm in
// headless Chromium on WebGPU and WebGL2, on the page's thread and in a
// worker, its canvas filling the page, the page resized in steps (a drag's,
// one a frame). Each frame that lays out a new size checked: the size of
// what was last drawn (WebGL2's draws to the canvas, WebGPU's
// getCurrentTexture; a worker's told over a BroadcastChannel) the canvas's
// displayed size in device pixels; else the frame shows the one before
// stretched (or cleared). On the page's thread none may be: an observer
// after the program's, the last before the paint, compares them. In a
// worker, whose frames reach the compositor on their own, a frame shows the
// newest draw before the next began, and at most one in ten may be stale,
// where its frames keep up with the steps (SwiftShader's WebGL2 in a worker
// draws one in about 300 ms: there only that a frame soon shows the last
// size). The frames' times printed (median, p95).
//   node tests/ui/web-resize.mjs <WebTodo.wasm>
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));
const [wasm] = process.argv.slice(2);
const src = (p) => path.join(here, '../../src/helder', p);
const files = {
	'/todo.wasm': wasm, '/os/browser.mjs': src('os/browser.mjs'), '/os/imports.mjs': src('os/imports.mjs'), '/os/thread.mjs': src('os/thread.mjs'),
	'/os/worker.mjs': src('os/worker.mjs'), '/gfx/imports.mjs': src('gfx/imports.mjs'), '/text/imports.mjs': src('text/imports.mjs'),
	'/ui/imports.mjs': src('ui/imports.mjs'), '/Inter.ttf': src('text/fonts/Inter.ttf'),
};
const types = { '.mjs': 'text/javascript', '.js': 'text/javascript', '.wasm': 'application/wasm', '.ttf': 'font/ttf' };
// (the draws' sizes, in the page and in its worker: a module the worker imports first)
const probe = `const main = typeof document !== 'undefined', ch = new BroadcastChannel('drawn');
const drawn = (w, h) => {
	const d = [performance.timeOrigin + performance.now(), w, h];
	if (main) self.drawn.push(d);
	else ch.postMessage(d);
};
for (const k of ['drawArrays', 'drawElements', 'drawArraysInstanced', 'drawElementsInstanced', 'clear']) {
	const f = WebGL2RenderingContext.prototype[k];
	WebGL2RenderingContext.prototype[k] = function (...a) {
		if (!this.getParameter(this.FRAMEBUFFER_BINDING)) drawn(this.drawingBufferWidth, this.drawingBufferHeight);
		return f.apply(this, a);
	};
}
if (self.GPUCanvasContext) {
	const f = GPUCanvasContext.prototype.getCurrentTexture;
	GPUCanvasContext.prototype.getCurrentTexture = function () {
		const t = f.call(this);
		drawn(t.width, t.height);
		return t;
	};
}
if (main) {
	self.drawn = [];
	ch.onmessage = (e) => self.drawn.push(e.data);
	const W = Worker;
	self.Worker = class extends W {
		constructor(url, o) {
			const s = 'import ' + JSON.stringify(location.origin + '/probe.js') + '; import ' + JSON.stringify(new URL(url, location.href).href) + ';';
			super(URL.createObjectURL(new Blob([s], { type: 'text/javascript' })), o);
		}
	};
}`;
const page = `<!doctype html><title>Resize</title><body style="margin:0; overflow:hidden">
<canvas id="c" style="width: 100vw; height: 100vh; display: block"></canvas>
<script type="module">
import './probe.js';
import { run } from './os/browser.mjs';
window.log = [];
window.frames = [];
window.resizes = [];
const loop = (t) => {
	requestAnimationFrame(loop);
	window.frames.push(performance.timeOrigin + t);
};
requestAnimationFrame(loop);
window.start = async (gfx, worker) => {
	window.result = await run('todo.wasm', { imports: ['os/imports.mjs', 'gfx/imports.mjs', 'text/imports.mjs', 'ui/imports.mjs'], canvas: 'c', gfx, worker,
		fonts: ['Inter.ttf'], stdout: (s) => window.log.push(s), stderr: (s) => window.log.push('stderr: ' + s) });
	// (after the program's observer: what each frame lays out, once the program saw it)
	const c = document.getElementById('c');
	new ResizeObserver(() => {
		const d = window.drawn[window.drawn.length - 1];
		window.resizes.push([performance.timeOrigin + performance.now(), Math.round(c.clientWidth * devicePixelRatio), Math.round(c.clientHeight * devicePixelRatio), d?.[1], d?.[2]]);
	}).observe(c);
	return window.result.host.gfx.backend + (window.result.host.worker ? ' in a worker' : '');
};
window.frame = () => new Promise((ok) => requestAnimationFrame(() => ok()));
</script>`;
const server = createServer(async (req, res) => {
	const p = new URL(req.url, 'http://x').pathname;
	try {
		const b = p === '/' ? Buffer.from(page) : p === '/probe.js' ? Buffer.from(probe) : await readFile(files[p]);
		res.writeHead(200, { 'content-type': p === '/' ? 'text/html' : types[path.extname(p)] });
		res.end(b);
	} catch {
		res.writeHead(404);
		res.end();
	}
}).listen(0);
const browser = await pw.chromium.launch({ args: ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-angle=swiftshader'] });
let failed = 0;
const newest = (list, t) => {
	let r = null;
	for (const x of list) if (x[0] < t) r = x;
	return r;
};
for (const worker of [false, true]) for (const gfx of ['webgpu', 'webgl2']) {
	const mode = gfx + (worker ? ' in a worker' : '');
	const p = await browser.newPage({ viewport: { width: 640, height: 480 } });
	const errors = [];
	p.on('pageerror', (e) => errors.push(e.message));
	let line;
	try {
		await p.goto(`http://localhost:${server.address().port}/`);
		const backend = await p.evaluate(([g, w]) => window.start(g, w), [gfx, worker]);
		if (backend !== mode) errors.push('on ' + backend);
		await p.waitForFunction(() => window.log.some((l) => l.startsWith('boxes ')), null, { timeout: 20000 });
		await p.waitForTimeout(300);
		const t0 = await p.evaluate(() => performance.timeOrigin + performance.now());
		// (a drag's steps, narrower and shorter then back, a frame each)
		const n = 30;
		for (let i = 1; i <= n; i++) {
			const k = Math.sin((i / n) * Math.PI);
			await p.setViewportSize({ width: Math.round(640 - 240 * k), height: Math.round(480 - 120 * k) });
			await p.evaluate(() => window.frame());
		}
		// (settled: the newest draw at the newest size, a slow worker's a few of its frames on)
		await p.waitForFunction(() => {
			const r = window.resizes[window.resizes.length - 1], d = window.drawn[window.drawn.length - 1];
			return r && d && r[1] === d[1] && r[2] === d[2];
		}, null, { timeout: 5000 }).catch(() => {});
		const { frames, resizes, drawn } = await p.evaluate(() => ({ frames: window.frames, resizes: window.resizes, drawn: window.drawn }));
		const times = [];
		for (let i = 0; i < frames.length - 1; i++) if (frames[i] >= t0) times.push(frames[i + 1] - frames[i]);
		let shown = 0, stale = 0;
		const late = [];
		if (!worker) for (const r of resizes) {
			if (r[0] < t0) continue;
			shown++;
			if (r[1] !== r[3] || r[2] !== r[4]) stale++;
		}
		// (a worker's: frame i shows the newest size laid out and the newest draw before frame i + 1 began)
		else for (let i = 0; i < frames.length - 1; i++) {
			if (frames[i] < t0) continue;
			const r = newest(resizes, frames[i + 1]), d = newest(drawn, frames[i + 1]);
			if (!r) continue;
			shown++;
			if (d && d[1] === r[1] && d[2] === r[2]) continue;
			stale++;
			// (how late: the resize seen this far into its frame, its size drawn this long after the next began)
			const later = resizes.filter((x) => x[0] >= r[0]).map((x) => x[1] + 'x' + x[2]);
			const at = drawn.find((x) => x[0] > r[0] && later.includes(x[1] + 'x' + x[2]));
			late.push([r[0] - frames[i], at ? at[0] - frames[i + 1] : Infinity]);
		}
		times.sort((a, b) => a - b);
		const at = (q) => times[Math.min(times.length - 1, Math.floor(q * times.length))].toFixed(1);
		const sizes = new Set(resizes.filter((r) => r[0] > t0).map((r) => r[1] + 'x' + r[2])).size;
		// (the worker's frames: their gaps while resized, at most two of the page's frames each when it keeps up)
		const gaps = drawn.filter((d) => d[0] > t0).map((d, i, a) => (i ? d[0] - a[i - 1][0] : 0)).filter((g) => g > 1).sort((a, b) => a - b);
		const keeps = gaps.length > 0 && gaps[gaps.length >> 1] < 40;
		const last = resizes[resizes.length - 1], end = drawn[drawn.length - 1];
		const settled = !!end && end[1] === last[1] && end[2] === last[2];
		const ok = errors.length === 0 && sizes >= n / 2 && settled && (!worker ? stale === 0 : !keeps || stale * 10 <= shown);
		if (!ok) failed++;
		const ms = (v) => (v === Infinity ? 'never' : v.toFixed(1));
		const how = late.length ? ` (seen ${late.map((l) => ms(l[0])).join(' ')} ms into their frames, drawn ${late.map((l) => ms(l[1])).join(' ')} ms after the next began)` : '';
		line = `${mode}: ${sizes} sizes, ${shown} frames, ${stale} at a stale size${how}${worker && !keeps ? ' (its frames slower than the steps)' : ''}${settled ? '' : ', the last not at the last size'}; frame times median ${at(0.5)} ms, p95 ${at(0.95)} ms${ok ? '' : ' FAILED'}`;
	} catch (e) {
		failed++;
		line = `${mode}: ${e.message} FAILED`;
	}
	console.log('web-resize.mjs: ' + line);
	for (const e of errors) console.log('  error: ' + e);
	await p.close();
}
await browser.close();
server.close();
process.exit(failed ? 1 : 0);
