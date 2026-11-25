// A canvas resized with the page (bun run test ui-web): WebTodo.wasm in
// headless Chromium on WebGPU and WebGL2, on the page's thread and in a
// worker, its canvas filling the page, the page resized in steps (a drag's,
// one a frame). Each frame that lays out a new size checked: the size of
// what was last drawn (WebGL2's draws to the canvas, WebGPU's
// getCurrentTexture; a worker's told over a BroadcastChannel) the canvas's
// displayed size in device pixels; else the frame shows the one before
// stretched (or cleared). On the page's thread none may be: an observer
// after the program's, the last before the paint, compares them (an
// order, not a time: the program draws in its own, before). In a worker,
// whose frames reach the compositor on their own, a frame shows the newest
// draw before the next began (its size laid out as the page's resize event
// told the worker, before its observer's): on a GPU at most one in ten
// stale, none drawn more than a frame late. On SwiftShader (the renderer
// WebGL names: CI's browser lanes, which have no GPU; their headless frame
// times are no GPU's either) that is printed, not checked: a loaded runner
// drawing in software gave 4 and then 22 stale of 30 on the same code. Both
// check what is so on any GPU: the last size drawn, none drawn at a size the
// page did not lay out, a worker's canvas drawn after each resize (none
// shown cleared) and drawing on (no gap of a second). The frames' times
// printed (median, p95); a worker's failed run (TRACE=1: each) its trace
// around its longest wait between draws.
//   node tests/ui/web-resize.mjs <WebTodo.wasm>   (CHROMIUM_ARGS: Chromium's flags, a GPU's)
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
// (the worker's trace, printed when a run fails: its messages, animation
// frames, timers, the canvas's resizes and GL calls of more than 5 ms)
const tr = new BroadcastChannel('trace'), now = () => performance.timeOrigin + performance.now();
const log = (k, d, t0) => tr.postMessage([t0 ?? now(), k, d, t0 === undefined ? 0 : now() - t0]);
if (!main) {
	self.probeLog = log;
	const raf = self.requestAnimationFrame?.bind(self), st = self.setTimeout.bind(self);
	if (raf) self.requestAnimationFrame = (f) => raf((t) => {
		const t0 = now();
		f(t);
		log('raf', '', t0);
	});
	self.setTimeout = (f, ms, ...a) => st(typeof f !== 'function' ? f : () => {
		const t0 = now();
		f(...a);
		log('timer', ms, t0);
	}, ms);
	for (const k of ['width', 'height']) {
		const d = Object.getOwnPropertyDescriptor(OffscreenCanvas.prototype, k);
		Object.defineProperty(OffscreenCanvas.prototype, k, { ...d, set(v) {
			const t0 = now();
			d.set.call(this, v);
			log('canvas.' + k, v, t0);
		} });
	}
	const G = WebGL2RenderingContext.prototype;
	for (const k of Object.getOwnPropertyNames(G)) {
		const f = Object.getOwnPropertyDescriptor(G, k).value;
		if (typeof f !== 'function' || k === 'constructor') continue;
		G[k] = function (...a) {
			const t0 = now(), r = f.apply(this, a);
			if (now() - t0 > 5) log('gl.' + k, '', t0);
			return r;
		};
	}
	addEventListener('message', (e) => log('message', e.data?.type ?? ''));
}
if (main) {
	self.drawn = [];
	self.trace = [];
	ch.onmessage = (e) => self.drawn.push(e.data);
	tr.onmessage = (e) => self.trace.push(e.data);
	const W = Worker, post = W.prototype.postMessage;
	W.prototype.postMessage = function (m, t) {
		self.trace.push([now(), 'posted', m?.type + (m?.type === 'size' ? ' ' + m.w + 'x' + m.hh : ''), 0]);
		return post.call(this, m, t);
	};
	self.Worker = class extends W {
		constructor(url, o) {
			// (the probe first, then the worker; a listener after the worker's own: each message's end)
			const s = 'import ' + JSON.stringify(location.origin + '/probe.js') + '; import ' + JSON.stringify(new URL(url, location.href).href)
				+ '; addEventListener("message", (e) => self.probeLog("handled", e.data?.type ?? "", performance.timeOrigin + performance.now()));';
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
window.ran = [];
window.resizes = [];
const loop = (t) => {
	requestAnimationFrame(loop);
	window.frames.push(performance.timeOrigin + t);
	window.ran.push(performance.timeOrigin + performance.now());
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
	// (in a worker: the size the page's resize event told it, before the observer's, which may come frames on)
	if (worker) addEventListener('resize', () => {
		const d = window.drawn[window.drawn.length - 1];
		window.resizes.push([performance.timeOrigin + performance.now(), Math.round(c.clientWidth * devicePixelRatio), Math.round(c.clientHeight * devicePixelRatio), d?.[1], d?.[2]]);
	});
	return window.result.host.gfx.backend + (window.result.host.worker ? ' in a worker' : '');
};
// (the GL renderer, as WebGL tells it: SwiftShader's in CI and headless)
window.renderer = () => {
	const g = document.createElement('canvas').getContext('webgl2'), x = g?.getExtension('WEBGL_debug_renderer_info');
	return g ? g.getParameter(x ? x.UNMASKED_RENDERER_WEBGL : g.RENDERER) : 'none';
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
// (CHROMIUM_ARGS: others, a GPU's: "--enable-unsafe-webgpu --enable-gpu --ignore-gpu-blocklist", the timing then checked)
const args = process.env.CHROMIUM_ARGS?.split(' ') ?? ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-angle=swiftshader'];
const browser = await pw.chromium.launch({ args });
let failed = 0, renderer = null;
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
	const trail = [];
	try {
		await p.goto(`http://localhost:${server.address().port}/`);
		renderer ??= await p.evaluate(() => window.renderer());
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
		const { frames, ran, resizes, drawn, trace } = await p.evaluate(() => ({ frames: window.frames, ran: window.ran, resizes: window.resizes, drawn: window.drawn, trace: window.trace }));
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
			// (how late: the resize seen this far into its frame, its size (or one
			// laid out after it, before the draw: the drag's sizes come back on
			// its way out) drawn this long after the next began)
			const at = drawn.find((x) => x[0] > r[0] && resizes.some((y) => y[0] >= r[0] && y[0] <= x[0] && y[1] === x[1] && y[2] === x[2]));
			late.push([r[0] - frames[i], at ? at[0] - frames[i + 1] : Infinity]);
		}
		times.sort((a, b) => a - b);
		const at = (q) => times[Math.min(times.length - 1, Math.floor(q * times.length))].toFixed(1);
		const sizes = new Set(resizes.filter((r) => r[0] > t0).map((r) => r[1] + 'x' + r[2])).size;
		// (the worker's frames: their gaps while resized)
		const t1 = resizes[resizes.length - 1][0] + 50;
		const gaps = drawn.filter((d) => d[0] > t0 && d[0] < t1).map((d, i, a) => (i ? d[0] - a[i - 1][0] : 0)).filter((g) => g > 1).sort((a, b) => a - b);
		const last = resizes[resizes.length - 1], end = drawn[drawn.length - 1];
		const settled = !!end && end[1] === last[1] && end[2] === last[2];
		// (none drawn at a size the page had not laid out by the end of its frame: on
		// the page's thread the program draws in its observer, before the test's;
		// the frame ends when the next one's callbacks run, not at its timestamp,
		// its begin, which comes before the last frame's observers when late)
		const by = (t) => ran.find((f) => f > t) ?? Infinity;
		const odd = drawn.filter((d) => d[0] > t0 && !resizes.some((r) => r[0] <= by(d[0]) && r[1] === d[1] && r[2] === d[2])).length;
		// (a worker's canvas resized and not drawn within 50 ms: shown cleared)
		const sets = trace.filter((e) => e[0] > t0 && e[1].startsWith('canvas.'));
		const blank = sets.filter((e) => !drawn.some((d) => d[0] > e[0] && d[0] < e[0] + e[3] + 50)).length;
		const longest = gaps[gaps.length - 1] ?? 0;
		// (on a GPU: a frame, the page's median (1 ms more: the two threads' clocks), the most a stale one's draw may come late)
		const soft = /SwiftShader/.test(renderer), frame = times[times.length >> 1] + 1;
		const timely = stale * 10 <= shown && late.every((l) => l[1] <= frame);
		const ok = errors.length === 0 && sizes >= n / 2 && settled && odd === 0
			&& (!worker ? stale === 0 : blank === 0 && longest < 1000 && (soft || timely));
		if (!ok) failed++;
		const ms = (v) => (v === Infinity ? 'never' : v.toFixed(1));
		// (a worker's longest wait between draws while resized: a stall)
		const stall = worker && gaps.length ? `, its longest gap between draws ${gaps[gaps.length - 1].toFixed(1)} ms` : '';
		const how = late.length ? ` (seen ${late.map((l) => ms(l[0])).join(' ')} ms into their frames, drawn ${late.map((l) => ms(l[1])).join(' ')} ms after the next began)` : '';
		// (a failed worker's run: its trace around its longest wait between draws)
		if (worker && (!ok || process.env.TRACE)) {
			const ds = drawn.filter((d) => d[0] > t0 && d[0] < t1);
			let k = 1;
			for (let i = 2; i < ds.length; i++) if (ds[i][0] - ds[i - 1][0] > ds[k][0] - ds[k - 1][0]) k = i;
			const from = (ds[k - 1]?.[0] ?? t0) - 30, to = (ds[k]?.[0] ?? t1) + 5;
			const events = [...trace, ...frames.map((f) => [f, 'page frame', '', 0]), ...resizes.map((r) => [r[0], 'laid out', r[1] + 'x' + r[2], 0]),
				...drawn.map((d) => [d[0], 'drew', d[1] + 'x' + d[2], 0])].filter((e) => e[0] >= from && e[0] <= to).sort((a, b) => a[0] - b[0]);
			trail.push(`  the worker's trace from 30 ms before its longest gap (${(ds[k][0] - ds[k - 1][0]).toFixed(1)} ms, from +30.0):`);
			for (const e of events.slice(0, 160)) trail.push(`    +${(e[0] - from).toFixed(1)} ${e[1]} ${e[2] ?? ''}${e[3] ? ' (' + e[3].toFixed(1) + ' ms)' : ''}`);
		}
		line = `${mode}: ${sizes} sizes, ${shown} frames, ${stale} at a stale size${how}${stall}${worker && soft ? ' (SwiftShader: timing reported, not checked)' : ''}${settled ? '' : ', the last not at the last size'}${odd ? `, ${odd} drawn at a size not laid out` : ''}${blank ? `, ${blank} resizes not drawn (shown cleared)` : ''}; frame times median ${at(0.5)} ms, p95 ${at(0.95)} ms${ok ? '' : ' FAILED'}`;
	} catch (e) {
		failed++;
		line = `${mode}: ${e.message} FAILED`;
	}
	console.log('web-resize.mjs: ' + line);
	for (const t of trail) console.log(t);
	for (const e of errors) console.log('  error: ' + e);
	await p.close();
}
console.log('web-resize.mjs: on ' + renderer);
await browser.close();
server.close();
process.exit(failed ? 1 : 0);
