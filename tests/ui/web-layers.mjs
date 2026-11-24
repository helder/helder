// The browser as the compositor (bun run test ui-web): WebLayersPage.wasm
// in headless Chromium, on WebGPU and WebGL2, on the page's thread and in
// a worker: the list's content a layer of the page's in its scroll view
// (tiles: more than one), what is over it a layer of its own; the page as
// shown (a screenshot) the same as with every layer on the window's
// (HELDER_SYSTEM_LAYERS=flat), at rest and scrolled by the wheel; in a
// worker, the list scrolled by the wheel while the program is busy (B):
// shown moved at once, as the program draws it once it is done; a frame
// read back (host.gfx.readPixels) drawn whole, as the flat window's.
//   node tests/ui/web-layers.mjs <WebLayersPage.wasm>
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
	'/layers.wasm': wasm, '/os/browser.mjs': src('os/browser.mjs'), '/os/imports.mjs': src('os/imports.mjs'), '/os/thread.mjs': src('os/thread.mjs'),
	'/os/worker.mjs': src('os/worker.mjs'), '/gfx/imports.mjs': src('gfx/imports.mjs'), '/text/imports.mjs': src('text/imports.mjs'),
	'/ui/imports.mjs': src('ui/imports.mjs'), '/Inter.ttf': src('text/fonts/Inter.ttf'),
};
const types = { '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.ttf': 'font/ttf' };
const page = `<!doctype html><title>Layers</title><body style="margin:0">
<canvas id="c" style="width: 400px; height: 300px; display: block"></canvas>
<script type="module">
import { run } from './os/browser.mjs';
window.log = [];
window.start = async (gfx, worker, flat) => {
	window.result = await run('layers.wasm', { imports: ['os/imports.mjs', 'gfx/imports.mjs', 'text/imports.mjs', 'ui/imports.mjs'], canvas: 'c', gfx, worker,
		fonts: ['Inter.ttf'], env: flat ? { HELDER_SYSTEM_LAYERS: 'flat' } : {}, stdout: (s) => window.log.push(s), stderr: (s) => window.log.push('stderr: ' + s) });
	return window.result.host.gfx.backend;
};
// (two screenshots' pixels: how many differ by more than 24 in a channel, within x0..x1, y0..y1)
const pixels = async (b64) => {
	const b = await createImageBitmap(await (await fetch('data:image/png;base64,' + b64)).blob());
	const c = new OffscreenCanvas(b.width, b.height), g = c.getContext('2d');
	g.drawImage(b, 0, 0);
	return g.getImageData(0, 0, b.width, b.height);
};
window.diff = async (a, b, x0, y0, x1, y1) => {
	const p = await pixels(a), q = await pixels(b);
	let n = 0;
	for (let y = y0; y < y1; y++)
		for (let x = x0; x < x1; x++) {
			const i = (y * p.width + x) * 4;
			if (Math.abs(p.data[i] - q.data[i]) > 24 || Math.abs(p.data[i + 1] - q.data[i + 1]) > 24 || Math.abs(p.data[i + 2] - q.data[i + 2]) > 24) n++;
		}
	return n;
};
// (the next frame read back, a hash)
window.read = async () => {
	const pixels = window.result.host.gfx.readPixels();
	window.result.host.os.redraw();
	const d = (await pixels).data;
	let h = 0;
	for (let i = 0; i < d.length; i++) h = (Math.imul(h, 31) + d[i]) | 0;
	return h;
};
// (the list's scroll view and what its layer shows: the tiles in its spacer)
window.layers = () => {
	const l = document.querySelector('canvas').hxmcScrolls;
	const v = l && [...l.querySelectorAll('div')].find((d) => d.hxmcScroller);
	return { top: v ? v.scrollTop : -1, tiles: v ? v.querySelectorAll('canvas').length : 0, over: l ? [...l.children].filter((e) => !e.hxmcScroller && e.querySelector('canvas')).length : 0 };
};
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
const browser = await pw.chromium.launch({ args: ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-angle=swiftshader'] });
let failed = 0;
const check = (what, ok, detail = '') => {
	if (!ok) failed++;
	console.log(`web-layers.mjs: ${ok ? 'ok' : 'FAIL'}: ${what}${ok ? '' : ': ' + detail}`);
};

async function open(gfx, worker, flat) {
	const p = await browser.newPage({ viewport: { width: 400, height: 300 } });
	p.on('pageerror', (e) => check('no page error', false, e.message));
	await p.goto(url);
	const backend = await p.evaluate(([g, w, f]) => window.start(g, w, f), [gfx, worker, flat]);
	await p.waitForFunction(() => window.log.some((l) => l.startsWith('layers ')), null, { timeout: 15000 });
	await p.waitForTimeout(400);
	return { p, backend };
}
const shot = async (p) => (await p.screenshot({ clip: { x: 0, y: 0, width: 400, height: 300 } })).toString('base64');
const state = async (p) => (await p.evaluate(() => window.log)).filter((l) => l.startsWith('layers ')).pop();
// (the list's rows, less its scrollbar's edge, where helder draws its thumb)
const LIST = [0, 40, 380, 300];

try {
	for (const gfx of ['webgpu', 'webgl2'])
		for (const worker of [false, true]) {
			const mode = `${gfx}${worker ? ' in a worker' : ''}`;
			const { p, backend } = await open(gfx, worker, false);
			const { p: q } = await open(gfx, worker, true);
			check(`${mode}: on ${gfx}`, backend === gfx, backend);
			const l = await p.evaluate(() => window.layers());
			check(`${mode}: the list's content in its scroll view, in tiles; the button over it a layer`, l.tiles >= 2 && l.over >= 1, JSON.stringify(l));
			const flat = await q.evaluate(() => window.layers());
			check(`${mode}: flat: none`, flat.tiles === 0 && flat.over === 0, JSON.stringify(flat));
			const a = await shot(p), b = await shot(q);
			let n = await p.evaluate(([a, b]) => window.diff(a, b, 0, 0, 400, 300), [a, b]);
			check(`${mode}: shown as the flat window shows it`, n <= 40, `${n} pixels differ`);
			const [ra, rb] = [await p.evaluate(() => window.read()), await q.evaluate(() => window.read())];
			check(`${mode}: a frame read back drawn whole, as the flat window's`, ra === rb, `${ra} and ${rb}`);
			// (the wheel over the list, on both)
			for (const r of [p, q]) {
				await r.mouse.move(150, 180);
				await r.mouse.wheel(0, 300);
			}
			await p.waitForTimeout(600);
			const s0 = await state(p), s1 = await state(q);
			n = await p.evaluate(([a, b]) => window.diff(a, b, 0, 0, 400, 300), [await shot(p), await shot(q)]);
			check(`${mode}: scrolled, shown as the flat window shows it`, s0 === s1 && s0.includes('list=300') && n <= 40, `${s0}, flat ${s1}; ${n} pixels differ`);
			if (worker) {
				// (the program busy: the browser scrolls the list's layer, the program draws nothing)
				await p.mouse.click(200, 20);
				const before = await shot(p), top0 = (await p.evaluate(() => window.layers())).top;
				await p.keyboard.press('b');
				await p.waitForTimeout(100);
				await p.mouse.move(150, 180);
				await p.mouse.wheel(0, -200);
				await p.waitForTimeout(400);
				const during = await shot(p), top1 = (await p.evaluate(() => window.layers())).top, busy = await state(p);
				await p.waitForTimeout(1800);
				const after = await shot(p), done = await state(p);
				const moved = await p.evaluate(([a, b, r]) => window.diff(a, b, ...r), [before, during, LIST]);
				const same = await p.evaluate(([a, b, r]) => window.diff(a, b, ...r), [during, after, LIST]);
				check(`${mode}: scrolled while the program is busy: shown at once, as the program then draws it`,
					top1 < top0 && !busy.includes('busy=1') && moved > 1000 && same <= 40 && done.includes('busy=1'), `top ${top0} -> ${top1}, ${busy} -> ${done}; moved ${moved}, then ${same} differ`);
			}
			await p.close();
			await q.close();
		}
} finally {
	await browser.close();
	server.close();
}
console.log(failed ? `web-layers.mjs: ${failed} FAILED` : 'web-layers.mjs: ok');
process.exit(failed ? 1 : 0);
