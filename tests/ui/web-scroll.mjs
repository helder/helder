// The browser's scroll views driving the scrollers (bun run test ui-web):
// WebScrollPage.wasm in headless Chromium, its scrollers the page's own
// elements over the canvas (WebScroll), driven by real events: the wheel
// scrolls the row and the page natively, the program following (a scroller
// out of sight losing its view); a click
// over a scroll view still reaches the program's button; a wheel with
// Control is the program's (no scroll); the keys' scroll (End) moves the
// element too; a touch's swipe pans the page, but not over the slider,
// which takes the drag (its moves the program's).
//   node tests/ui/web-scroll.mjs <WebScrollPage.wasm>
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
const files = {
	'/scroll.wasm': wasm,
	'/os/browser.mjs': path.join(here, '../../src/helder/os/browser.mjs'),
	'/os/imports.mjs': path.join(here, '../../src/helder/os/imports.mjs'),
	'/os/thread.mjs': path.join(here, '../../src/helder/os/thread.mjs'),
	'/os/worker.mjs': path.join(here, '../../src/helder/os/worker.mjs'),
	'/gfx/imports.mjs': path.join(here, '../../src/helder/gfx/imports.mjs'),
	'/text/imports.mjs': path.join(here, '../../src/helder/text/imports.mjs'),
	'/ui/imports.mjs': path.join(here, '../../src/helder/ui/imports.mjs'),
	'/Inter.ttf': path.join(here, '../../src/helder/text/fonts/Inter.ttf'),
};
const types = { '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.ttf': 'font/ttf' };
const page = `<!doctype html><title>Scroll</title><body style="margin:0">
<canvas id="c" style="width: 400px; height: 300px; display: block"></canvas>
<script type="module">
import { run } from './os/browser.mjs';
window.log = [];
window.start = async (worker) => {
	window.r = run('scroll.wasm', { imports: ['os/imports.mjs', 'gfx/imports.mjs', 'text/imports.mjs', 'ui/imports.mjs'], canvas: 'c', gfx: 'webgl2', worker,
		fonts: ['Inter.ttf'], stdout: (s) => window.log.push(s), stderr: (s) => window.log.push('stderr: ' + s) });
	window.result = await window.r;
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
const browser = await pw.chromium.launch({ args: ['--use-angle=swiftshader'] });
let failed = 0, worker = false;
const check = (what, ok, detail = '') => {
	if (!ok) {
		failed++;
		console.log('web-scroll: FAIL' + (worker ? ' (in a worker)' : '') + ': ' + what + (detail ? ': ' + detail : ''));
	}
};

async function open(options) {
	const ctx = await browser.newContext(options);
	const p = await ctx.newPage();
	p.on('pageerror', (e) => check('no page error', false, e.message));
	await p.goto(url);
	await p.evaluate((w) => window.start(w), worker);
	await p.waitForFunction(() => window.log.some((l) => l.startsWith('scroll ')) && document.querySelector('canvas').hxmcScrolls, null, { timeout: 15000 });
	await p.waitForTimeout(200);
	return { ctx, p };
}

// the program's state (its last line) and the scroll views' offsets (CSS pixels: the page's, the row's)
async function state(p) {
	await p.waitForTimeout(300);
	const line = (await p.evaluate(() => window.log)).filter((l) => l.startsWith('scroll ')).pop();
	const s = {};
	for (const m of line.matchAll(/(\w+)=(-?[\d.]+)/g)) s[m[1]] = Number(m[2]);
	const views = await p.evaluate(() => [...document.querySelector('canvas').hxmcScrolls.querySelectorAll('div')].filter((e) => e.hxmcScroller)
		.map((e) => [e.scrollTop, e.scrollLeft]));
	return { ...s, views };
}

// (the page's thread, then the program in a worker)
try { for (worker of [false, true]) {
	// a desktop's wheel, clicks and keys
	{
		const { ctx, p } = await open({ viewport: { width: 400, height: 300 } });
		let s = await state(p);
		check('two scroll views, the row inside the page', s.views.length === 2, JSON.stringify(s.views));
		await p.mouse.move(200, 40);
		await p.mouse.wheel(150, 0);
		s = await state(p);
		check('a sideways wheel over the row scrolls the row', s.row > 0 && s.page === 0 && Math.abs(s.views[1][1] - s.row) < 1, JSON.stringify(s));
		await p.mouse.move(200, 200);
		await p.mouse.wheel(0, 120);
		s = await state(p);
		check('the wheel scrolls the page natively, the program following', s.page > 0 && Math.abs(s.views[0][0] - s.page) < 1, JSON.stringify(s));
		check('the row, scrolled out of sight, without a view', s.views.length === 1, JSON.stringify(s.views));
		// (the button: row 3, below the cards, 80 + 3 * 40, less the page's scroll)
		await p.mouse.click(200, 80 + 3 * 40 + 20 - s.page);
		s = await state(p);
		check('a click over the scroll view reaches the program', s.clicks === 1, JSON.stringify(s));
		const before = s.page;
		await p.keyboard.down('Control');
		await p.mouse.wheel(0, 100);
		await p.keyboard.up('Control');
		s = await state(p);
		check('a wheel with Control the program\'s, no scroll', s.wheels >= 1 && s.page === before, JSON.stringify(s));
		await p.keyboard.press('End');
		s = await state(p);
		check('the keys\' scroll moves the scroll view', s.page > before && Math.abs(s.views[0][0] - s.page) < 1, JSON.stringify(s));
		// (a popup over the page, centred, 160 by 120 (120, 90 to 280, 210): the scroll view keeps its scrollbar, the popup's box
		// cut out of it, where a wheel is the popup's, not the page's)
		const view = () => p.evaluate(() => {
			const e = [...document.querySelector('canvas').hxmcScrolls.querySelectorAll('div')].find((d) => d.hxmcScroller);
			return { events: e.style.pointerEvents, bar: e.classList.contains('hxmc-nobar'), clip: e.style.clipPath, top: e.scrollTop };
		});
		await p.keyboard.press('Home');
		s = await state(p);
		check('the keys\' glide not stopped by its own scroll told back (Home: at the top)', s.page === 0, JSON.stringify(s));
		await p.keyboard.press('m');
		await p.waitForTimeout(300);
		let v = await view();
		check('under a popup: input kept, the popup cut out', v.events === 'auto' && v.clip.includes('path(evenodd'), JSON.stringify(v));
		await p.waitForTimeout(300);
		const at = (await state(p)).page;
		await p.mouse.move(200, 150);
		await p.mouse.wheel(0, 120);
		s = await state(p);
		check('a wheel over the popup is the popup\'s, nothing under it scrolled', s.page === at && s.popup >= 1, JSON.stringify(s));
		await p.mouse.move(60, 250);
		await p.mouse.wheel(0, 120);
		s = await state(p);
		check('beside it the page scrolls natively', s.page > at, JSON.stringify(s));
		await p.keyboard.press('Escape');
		await p.waitForTimeout(300);
		v = await view();
		check('the popup closed: nothing cut out', v.clip === '' || v.clip === 'none', JSON.stringify(v));
		await ctx.close();
	}
	// a phone's swipes
	{
		const { ctx, p } = await open({ viewport: { width: 400, height: 300 }, hasTouch: true, isMobile: true });
		const cdp = await ctx.newCDPSession(p);
		const swipe = async (x, y0, y1) => {
			await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y: y0 }] });
			for (let i = 1; i <= 10; i++) {
				await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: y0 + (y1 - y0) * i / 10 }] });
				await p.waitForTimeout(16);
			}
			await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
		};
		// (the slider: row 2, at 80 + 2 * 40)
		await swipe(200, 80 + 2 * 40 + 20, 40);
		let s = await state(p);
		check('a swipe over the slider is the program\'s', s.page === 0 && s.moves > 0, JSON.stringify(s));
		await swipe(200, 280, 120);
		await p.waitForTimeout(500);
		s = await state(p);
		check('a swipe pans the page natively, the program following', s.page > 0 && Math.abs(s.views[0][0] - s.page) < 1, JSON.stringify(s));
		await ctx.close();
	}
} } finally {
	await browser.close();
	server.close();
}
console.log(failed ? `web-scroll: ${failed} failed` : 'web-scroll: ok');
process.exit(failed ? 1 : 0);
