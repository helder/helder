// The pointer's shape in a browser (bun run test ui-web): WebCursorPage.wasm
// in headless Chromium, the mouse moved over each of its nodes, the cursor
// the program gave the canvas (Window.cursor: its CSS cursor) read there: a
// hand over the button and the link (Ui.pressCursor, a browser's), the
// arrow over the disabled button and plain text, the I-beam over the field.
// With worker, the program in a worker (browser.mjs's option worker).
//   node tests/ui/web-cursor.mjs <WebCursorPage.wasm> [worker]
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const here = path.dirname(fileURLToPath(import.meta.url));
const [wasm, thread] = process.argv.slice(2), worker = thread === 'worker', mode = worker ? ' (in a worker)' : '';
const src = (p) => path.join(here, '../../src/helder', p);
const files = {
	'/cursor.wasm': wasm, '/os/browser.mjs': src('os/browser.mjs'), '/os/imports.mjs': src('os/imports.mjs'), '/os/thread.mjs': src('os/thread.mjs'),
	'/os/worker.mjs': src('os/worker.mjs'), '/gfx/imports.mjs': src('gfx/imports.mjs'), '/text/imports.mjs': src('text/imports.mjs'),
	'/ui/imports.mjs': src('ui/imports.mjs'), '/Inter.ttf': src('text/fonts/Inter.ttf'),
};
const types = { '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.ttf': 'font/ttf' };
const page = `<!doctype html><title>Cursor</title><body style="margin:0">
<canvas id="c" style="width: 400px; height: 100px; display: block"></canvas>
<script type="module">
import { run } from './os/browser.mjs';
window.log = [];
window.start = async (worker) => {
	window.result = await run('cursor.wasm', { imports: ['os/imports.mjs', 'gfx/imports.mjs', 'text/imports.mjs', 'ui/imports.mjs'], canvas: 'c', gfx: 'webgl2', worker,
		fonts: ['Inter.ttf'], stdout: (s) => window.log.push(s), stderr: (s) => window.log.push('stderr: ' + s) });
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
const browser = await pw.chromium.launch({ args: ['--use-angle=swiftshader'] });
const p = await browser.newPage({ viewport: { width: 420, height: 120 } });
const errors = [];
p.on('pageerror', (e) => errors.push(e.message));
const want = { save: 'pointer', off: 'default', link: 'pointer', field: 'text', plain: 'default' };
const got = {};
try {
	await p.goto(`http://localhost:${server.address().port}/`);
	await p.evaluate((w) => window.start(w), worker);
	await p.waitForFunction(() => window.log.some((l) => l.startsWith('boxes ') && l.includes('plain=')), null, { timeout: 20000 });
	const line = (await p.evaluate(() => window.log)).filter((l) => l.startsWith('boxes ')).pop();
	const boxes = Object.fromEntries(line.slice(6).split(' ').map((s) => s.split('=')).map(([k, v]) => [k, v.split(',').map(Number)]));
	for (const tag of Object.keys(want)) {
		const [x, y, w, h] = boxes[tag];
		await p.mouse.move(x + w / 2, y + h / 2);
		// (the cursor follows at the next frame, the worker's a message later)
		await p.waitForFunction((c) => document.getElementById('c').style.cursor === c, want[tag], { timeout: 2000 }).catch(() => {});
		got[tag] = await p.evaluate(() => document.getElementById('c').style.cursor);
	}
} catch (e) {
	errors.push(String(e));
}
await browser.close();
server.close();
const wrong = Object.keys(want).filter((k) => got[k] !== want[k]);
console.log(`web-cursor.mjs${mode}: ${Object.entries(got).map(([k, v]) => `${k} ${v}`).join(', ')}${wrong.length || errors.length ? ' FAILED' : ''}`);
for (const k of wrong) console.log(`  ${k}: ${got[k]}, not ${want[k]}`);
for (const e of errors) console.log('  error: ' + e);
process.exit(wrong.length || errors.length ? 1 : 0);
