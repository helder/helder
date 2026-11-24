// The program on the page's thread against the program in a worker
// (bun run test thread-web; not in CI): ThreadBench.wasm in headless
// Chromium, Firefox and WebKit (those Playwright has), on each thread, on
// WebGL2 (where WebGPU is not in every engine): the time to its first
// frame; 150 pointer moves 16 ms apart, the time from each move's event
// on the page to the end of the frame that took it (input), and each
// frame's own time; the same while the page's thread is busy 30 ms of
// every 50 (page busy: a page's own scripts), and the frames' rate then.
// First a still on each thread (--still), whose pixels must be the same.
// Prints a table (ms: medians, p95 in brackets) and, with --json f, writes it.
//   node tests/ui/thread-bench.mjs <ThreadBench.wasm> [--json out.json]
import { createServer } from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2), wasm = args[0], json = args.includes('--json') ? args[args.indexOf('--json') + 1] : null;
const src = (p) => path.join(here, '../../src/helder', p);
const files = {
	'/bench.wasm': wasm, '/os/browser.mjs': src('os/browser.mjs'), '/os/imports.mjs': src('os/imports.mjs'), '/os/thread.mjs': src('os/thread.mjs'),
	'/os/worker.mjs': src('os/worker.mjs'), '/gfx/imports.mjs': src('gfx/imports.mjs'), '/text/imports.mjs': src('text/imports.mjs'),
	'/ui/imports.mjs': src('ui/imports.mjs'), '/Inter.ttf': src('text/fonts/Inter.ttf'),
};
const types = { '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.ttf': 'font/ttf' };
const page = `<!doctype html><title>Bench</title><body style="margin:0">
<canvas id="c" style="width: 480px; height: 360px; display: block"></canvas>
<script type="module">
import { run } from './os/browser.mjs';
window.start = async (worker, still) => {
	const t0 = performance.now();
	window.timing = [];
	window.result = await run('bench.wasm', { imports: ['os/imports.mjs', 'gfx/imports.mjs', 'text/imports.mjs', 'ui/imports.mjs'], canvas: 'c', gfx: 'webgl2',
		worker, fonts: ['Inter.ttf'], timing: window.timing, args: still ? ['--still'] : [] });
	// (the first frame: its pixels read back, a frame asked for: a still one may have drawn it already)
	const first = window.result.host.gfx.readPixels();
	window.result.host.os.redraw();
	await first;
	return { first: performance.now() - t0, worker: !!window.result.host.worker };
};
// (the next frame's pixels, a hash)
window.still = async () => {
	const pixels = window.result.host.gfx.readPixels();
	window.result.host.os.redraw();
	const d = (await pixels).data;
	let h = 0;
	for (let i = 0; i < d.length; i++) h = (Math.imul(h, 31) + d[i]) | 0;
	return h;
};
window.frames = async () => (window.result.host.worker ? window.result.host.timing() : window.timing.slice());
// (the page's own scripts: busy ms of every period)
window.busy = (ms, period) => {
	window.busyTimer = setInterval(() => {
		const end = performance.now() + ms;
		while (performance.now() < end) {}
	}, period);
};
window.idle = () => clearInterval(window.busyTimer);
</script>`;
const server = createServer(async (req, res) => {
	const p = new URL(req.url, 'http://x').pathname;
	try {
		const b = p === '/' ? Buffer.from(page) : await readFile(files[p]);
		res.writeHead(200, { 'content-type': p === '/' ? 'text/html' : types[path.extname(p)] });
		res.end(b);
	} catch {
		res.writeHead(404);
		res.end();
	}
}).listen(0);
const url = `http://localhost:${server.address().port}/`;

const quantile = (a, q) => {
	if (!a.length) return NaN;
	const s = [...a].sort((x, y) => x - y);
	return s[Math.min(s.length - 1, Math.floor(q * s.length))];
};
const fmt = (a) => (a.length ? `${quantile(a, 0.5).toFixed(1)} (${quantile(a, 0.95).toFixed(1)})` : '-');

// the frames since `from`: each one that took an input newer than the one before, its latency; frame times; intervals
function measure(frames, from) {
	const f = frames.filter((x) => x[0] >= from);
	const input = [], ms = [], gaps = [];
	let last = 0;
	for (let i = 0; i < f.length; i++) {
		const [at, len, stamp] = f[i];
		ms.push(len);
		if (i > 0) gaps.push(at - f[i - 1][0]);
		if (stamp && stamp !== last && stamp >= from) input.push(at + len - stamp);
		last = stamp;
	}
	return { input, ms, gaps };
}

const results = [];
const engines = { chromium: { args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] }, firefox: {}, webkit: {} };
// (ENGINES=chromium,firefox: those alone)
const only = process.env.ENGINES?.split(',');
for (const [name, opts] of Object.entries(engines)) {
	if (only && !only.includes(name)) continue;
	let browser;
	try {
		browser = await pw[name].launch(opts);
	} catch (e) {
		console.log(`thread-bench: ${name}: not installed (${e.message.split('\n')[0]})`);
		continue;
	}
	// (a still on each thread: the same pixels)
	const stills = [];
	for (const worker of [false, true]) {
		const p = await browser.newPage({ viewport: { width: 480, height: 360 } });
		await p.goto(url);
		await p.evaluate((w) => window.start(w, true), worker);
		await p.mouse.move(100, 100);
		await p.waitForTimeout(300);
		stills.push(await p.evaluate(() => window.still()));
		await p.close();
	}
	const same = stills[0] === stills[1];
	for (const worker of [false, true]) {
		const p = await browser.newPage({ viewport: { width: 480, height: 360 } });
		const errors = [];
		p.on('pageerror', (e) => errors.push(e.message));
		await p.goto(url);
		const row = { engine: `${name} ${browser.version()}`, thread: worker ? 'worker' : 'page', same };
		try {
			const s = await p.evaluate((w) => window.start(w), worker);
			row.first = s.first;
			row.inWorker = s.worker;
			await p.waitForTimeout(500);
			const moves = async () => {
				const from = await p.evaluate(() => performance.timeOrigin + performance.now());
				for (let i = 0; i < 150; i++) {
					await p.mouse.move(40 + (i % 60) * 6, 60 + (i % 40) * 6);
					await p.waitForTimeout(16);
				}
				await p.waitForTimeout(200);
				return measure(await p.evaluate(() => window.frames()), from);
			};
			const idle = await moves();
			await p.evaluate(() => window.busy(30, 50));
			const busy = await moves();
			await p.evaluate(() => window.idle());
			Object.assign(row, { input: idle.input, frame: idle.ms, busyInput: busy.input, busyGaps: busy.gaps });
		} catch (e) {
			row.error = e.message.split('\n')[0];
		}
		if (errors.length) row.error = (row.error ? row.error + '; ' : '') + errors.join('; ');
		if (!same) row.error = (row.error ? row.error + '; ' : '') + 'the worker\'s pixels not the page\'s';
		results.push(row);
		await p.close();
	}
	await browser.close();
}
server.close();
console.log('| engine | thread | still | first frame | input → frame | frame | page busy: input → frame | page busy: frame interval |');
console.log('|---|---|---|---|---|---|---|---|');
for (const r of results)
	console.log(r.error && !r.input ? `| ${r.engine} | ${r.thread} | failed: ${r.error} ||||||`
		: `| ${r.engine} | ${r.thread}${r.thread === 'worker' && !r.inWorker ? ' (page: not fit)' : ''} | ${r.same ? 'same' : 'differs'} | ${r.first.toFixed(0)} | ${fmt(r.input)} | ${fmt(r.frame)} | ${fmt(r.busyInput)} | ${fmt(r.busyGaps)} |`);
if (json) await writeFile(json, JSON.stringify(results.map((r) => ({ ...r, input: fmt(r.input ?? []), frame: fmt(r.frame ?? []), busyInput: fmt(r.busyInput ?? []), busyGaps: fmt(r.busyGaps ?? []) })), null, 1));
process.exit(results.some((r) => r.error) ? 1 : 0);
