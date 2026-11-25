// A video between the browser's layers (bun run test ui-web):
// WebVideoLayers.wasm in headless Chromium on WebGL2, on the page's
// thread and in a worker: the video's frames on its system layer (a
// canvas of the page, helder.media's WebSample) while it plays, stacked
// between the window's canvas and the layer over it (the box drawn after
// the video, red where it covers the video's corner), the list a layer in
// its scroll view; the page's pixels: the video's where only it is, the
// box's where it covers it.
//   node tests/ui/web-video-layers.mjs <WebVideoLayers.wasm>
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
	'/video.wasm': wasm, '/long.webm': path.join(here, '../media/web/long.webm'), '/Inter.ttf': src('text/fonts/Inter.ttf'),
	...Object.fromEntries(['os/browser.mjs', 'os/imports.mjs', 'os/thread.mjs', 'os/worker.mjs', 'gfx/imports.mjs', 'text/imports.mjs', 'ui/imports.mjs', 'async/imports.mjs',
		'media/imports.mjs', 'jobs/imports.mjs', 'jobs/worker.mjs'].map((f) => ['/' + f, src(f)])),
};
const types = { '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.ttf': 'font/ttf', '.webm': 'video/webm' };
const page = `<!doctype html><title>Video</title><body style="margin:0">
<canvas id="c" style="width: 400px; height: 300px; display: block"></canvas>
<script type="module">
import { run } from './os/browser.mjs';
window.log = [];
window.start = async (worker) => {
	window.result = await run('video.wasm', { imports: ['os/imports.mjs', 'gfx/imports.mjs', 'text/imports.mjs', 'ui/imports.mjs', 'async/imports.mjs', 'media/imports.mjs', 'jobs/imports.mjs'],
		canvas: 'c', gfx: 'webgl2', worker, fonts: ['Inter.ttf'], stdout: (s) => window.log.push(s), stderr: (s) => window.log.push('stderr: ' + s) });
};
// (the slot's canvas and the layer over it: their z-indexes in the layer of scroll views)
window.stack = () => {
	const l = document.querySelector('canvas').hxmcScrolls, kids = l ? [...l.children] : [];
	const slot = kids.find((e) => e.tagName === 'CANVAS'), over = kids.filter((e) => e.tagName === 'DIV' && !e.hxmcScroller);
	return { slot: slot ? Number(slot.style.zIndex) : -1, shown: slot ? slot.style.display !== 'none' && slot.width > 0 : false, over: over.map((e) => Number(e.style.zIndex)),
		views: kids.filter((e) => e.hxmcScroller && e.querySelector('canvas')).length };
};
window.pixel = async (b64, x, y) => {
	const b = await createImageBitmap(await (await fetch('data:image/png;base64,' + b64)).blob());
	const c = new OffscreenCanvas(b.width, b.height).getContext('2d');
	c.drawImage(b, 0, 0);
	return [...c.getImageData(x, y, 1, 1).data].slice(0, 3);
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
const browser = await pw.chromium.launch({ args: ['--use-angle=swiftshader', '--autoplay-policy=no-user-gesture-required'] });
let failed = 0;
const check = (what, ok, detail = '') => {
	if (!ok) failed++;
	console.log(`web-video-layers.mjs: ${ok ? 'ok' : 'FAIL'}: ${what}${ok ? '' : ': ' + detail}`);
};
try {
	for (const worker of [false, true]) {
		const mode = worker ? 'in a worker' : 'on the page\'s thread';
		const p = await browser.newPage({ viewport: { width: 400, height: 300 } });
		p.on('pageerror', (e) => check(`${mode}: no page error`, false, e.message));
		await p.goto(url);
		await p.evaluate((w) => window.start(w), worker);
		const ok = await p.waitForFunction(() => window.log.some((l) => l.includes('frames=many layer=true')), null, { timeout: 20000 }).then(() => true, () => false);
		check(`${mode}: the video plays on its system layer`, ok, (await p.evaluate(() => window.log)).slice(-4).join(' / '));
		await p.waitForTimeout(300);
		const s = await p.evaluate(() => window.stack());
		check(`${mode}: its canvas between the window's and the layer over it, the list in its scroll view`, s.shown && s.slot > 0 && s.over.some((z) => z > s.slot) && s.views === 1, JSON.stringify(s));
		const shot = (await p.screenshot({ clip: { x: 0, y: 0, width: 400, height: 300 } })).toString('base64');
		const video = await p.evaluate(([b, x, y]) => window.pixel(b, x, y), [shot, 60, 60]), covered = await p.evaluate(([b, x, y]) => window.pixel(b, x, y), [shot, 230, 180]);
		const bg = video[0] === 0x33 && video[1] === 0x33 && video[2] === 0x33;
		check(`${mode}: the video's pixels shown, the box over its corner`, !bg && covered[0] > 200 && covered[1] < 60 && covered[2] < 60, `video ${video}, covered ${covered}`);
		await p.close();
	}
} finally {
	await browser.close();
	server.close();
}
console.log(failed ? `web-video-layers.mjs: ${failed} FAILED` : 'web-video-layers.mjs: ok');
process.exit(failed ? 1 : 0);
