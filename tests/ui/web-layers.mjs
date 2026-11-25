// The browser as the compositor (bun run test ui-web): WebLayersPage.wasm
// in headless Chromium, on WebGPU and WebGL2, on the page's thread and in
// a worker: the list's content a layer of the page's in its scroll view
// (tiles: more than one), what is over it a layer of its own; the page as
// shown (a screenshot) the same as with every layer on the window's
// (HELDER_SYSTEM_LAYERS=flat), at rest and scrolled by the wheel; in a
// worker, the list scrolled by the wheel while the program is busy (B):
// shown moved at once, as the program draws it once it is done; the box's
// slide (a layer that moves on its own: a Web Animation) going on while
// the program is busy, where the flat window's would not; a frame read
// back (host.gfx.readPixels) drawn whole, as the flat window's.
// A still that differs is saved in the out dir: its two screenshots and
// their difference (red where they differ).
//   node tests/ui/web-layers.mjs <WebLayersPage.wasm> [out dir]   (ENGINE=firefox, webkit: those)
import { createServer } from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));
const [wasm, out = 'bin/ui'] = process.argv.slice(2);
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
// (their difference as a PNG: b dimmed, red where they differ)
window.diffImage = async (a, b) => {
	const p = await pixels(a), q = await pixels(b), d = new ImageData(p.width, p.height);
	for (let i = 0; i < p.data.length; i += 4) {
		const off = [0, 1, 2].some((c) => Math.abs(p.data[i + c] - q.data[i + c]) > 24);
		d.data.set(off ? [255, 0, 0, 255] : [q.data[i] / 3, q.data[i + 1] / 3, q.data[i + 2] / 3, 255], i);
	}
	const c = new OffscreenCanvas(p.width, p.height);
	c.getContext('2d').putImageData(d, 0, 0);
	const u = new Uint8Array(await (await c.convertToBlob()).arrayBuffer());
	let s = '';
	for (const x of u) s += String.fromCharCode(x);
	return btoa(s);
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
// (the next frame read back, a hash, less the right 20 points: the list's scrollbar, the page's where they overlay)
window.read = async () => {
	const pixels = window.result.host.gfx.readPixels();
	window.result.host.os.redraw();
	const { data: d, width: w } = await pixels, edge = Math.round(w * 380 / 400);
	let h = 0;
	for (let i = 0; i < d.length; i++) if ((i >> 2) % w < edge) h = (Math.imul(h, 31) + d[i]) | 0;
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
// (ENGINE=firefox or webkit: that one, on WebGL2 alone; not in CI)
const engine = process.env.ENGINE ?? 'chromium';
const browser = await pw[engine].launch(engine === 'chromium' ? { args: ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-angle=swiftshader'] } : {});
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
// (two screenshots' differing pixels in region r; past 40, the two and their difference saved as name)
async function compare(p, name, a, b, r) {
	const n = await p.evaluate(([a, b, r]) => window.diff(a, b, ...r), [a, b, r]);
	if (n > 40) {
		const f = path.join(out, 'web-layers-' + name.replace(/\W+/g, '-'));
		await writeFile(f + '-layers.png', Buffer.from(a, 'base64'));
		await writeFile(f + '-flat.png', Buffer.from(b, 'base64'));
		await writeFile(f + '-diff.png', Buffer.from(await p.evaluate(([a, b]) => window.diffImage(a, b), [a, b]), 'base64'));
		console.log(`web-layers.mjs: saved ${f}-{layers,flat,diff}.png`);
	}
	return n;
}
const state = async (p) => (await p.evaluate(() => window.log)).filter((l) => l.startsWith('layers ')).pop();
// (the list's rows, less its scrollbar's edge, where helder draws its thumb; the
// window less that edge: the page's own scrollbars there where they overlay)
const LIST = [0, 40, 380, 300], FRAME = [0, 0, 380, 300];

try {
	for (const gfx of engine === 'chromium' ? ['webgpu', 'webgl2'] : ['webgl2'])
		for (const worker of [false, true]) {
			const mode = `${gfx}${worker ? ' in a worker' : ''}`;
			const { p, backend } = await open(gfx, worker, false);
			const { p: q } = await open(gfx, worker, true);
			check(`${mode}: on ${gfx}`, backend === gfx, backend);
			const l = await p.evaluate(() => window.layers());
			check(`${mode}: the list's content in its scroll view, in tiles; the button over it a layer`, l.tiles >= 2 && l.over >= 1, JSON.stringify(l));
			const flat = await q.evaluate(() => window.layers());
			check(`${mode}: flat: none`, flat.tiles === 0 && flat.over === 0, JSON.stringify(flat));
			// (the list's scrollbars: the browser's own where they overlay, its view holding the list's layer; else drawn)
			const bars = await p.evaluate(() => {
				const d = Object.assign(document.createElement('div'), { style: 'position:absolute;width:50px;height:50px;overflow:scroll' });
				document.body.appendChild(d);
				const overlay = d.offsetWidth === d.clientWidth;
				d.remove();
				const v = [...document.querySelector('canvas').hxmcScrolls.querySelectorAll('div')].find((e) => e.hxmcScroller);
				return { overlay, width: v.style.scrollbarWidth };
			});
			const said = await state(p), flatSaid = await state(q);
			check(`${mode}: the list's scrollbars the browser's where they overlay, else drawn`, bars.overlay ? bars.width === 'auto' && said.includes('bars=page')
				: bars.width === 'none' && said.includes('bars=drawn'), `${JSON.stringify(bars)}, ${said}`);
			check(`${mode}: flat: drawn`, flatSaid.includes('bars=drawn'), flatSaid);
			const a = await shot(p), b = await shot(q);
			let n = await compare(p, `${mode} still`, a, b, FRAME);
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
			n = await compare(p, `${mode} scrolled`, await shot(p), await shot(q), FRAME);
			check(`${mode}: scrolled, shown as the flat window shows it`, s0.split(' | ')[0] === s1.split(' | ')[0] && s0.includes('list=300') && n <= 40, `${s0}, flat ${s1}; ${n} pixels differ`);
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
				// (the box sliding, the program busy from a tenth of a second in: on the page, not on the flat window)
				// (the header within the window's edges: the busy scroll above left a focus ring on this one)
				const HEADER = [100, 3, 397, 37];
				const slides = [];
				for (const r of [p, q]) {
					await r.mouse.click(200, 20);
					await r.keyboard.press('m');
					await r.waitForTimeout(100);
					await r.keyboard.press('b');
					await r.waitForTimeout(150);
					const s0 = await shot(r);
					await r.waitForTimeout(400);
					slides.push(await r.evaluate(([a, b, h]) => window.diff(a, b, ...h), [s0, await shot(r), HEADER]));
					await r.waitForTimeout(1600);
				}
				check(`${mode}: a slide goes on while the program is busy, as a Web Animation`, slides[0] > 100 && slides[1] === 0, `${slides[0]} pixels moved, the flat window's ${slides[1]}`);
				const end = await p.evaluate(([a, b, h]) => window.diff(a, b, ...h), [await shot(p), await shot(q), HEADER]);
				check(`${mode}: slid, shown as the flat window shows it`, end <= 40, `${end} pixels differ`);
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
