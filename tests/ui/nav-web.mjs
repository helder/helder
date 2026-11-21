// helder.ui's Stack in headless Chromium (bun run test touch-web):
// NavWeb.wasm on a page that came after another (/start): each push an
// entry of the page's history with the screen's path; the history's back
// pops (the URL and the app's top together); Escape pops and the URL
// follows; a reload at /item/2 restores that screen over the root, whose
// back is the root's /; at the root the page's own back leaves it.
//   node tests/ui/nav-web.mjs <NavWeb.wasm>
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
// (helder's Inter, what a built page ships)
const font = path.join(here, '../../src/helder/text/fonts/Inter.ttf');
const files = {
	'/nav.wasm': wasm,
	'/os/browser.mjs': path.join(here, '../../src/helder/os/browser.mjs'),
	'/os/imports.mjs': path.join(here, '../../src/helder/os/imports.mjs'),
	'/gfx/imports.mjs': path.join(here, '../../src/helder/gfx/imports.mjs'),
	'/text/imports.mjs': path.join(here, '../../src/helder/text/imports.mjs'),
	'/ui/imports.mjs': path.join(here, '../../src/helder/ui/imports.mjs'),
	'/font.ttf': font,
};
const types = { '.mjs': 'text/javascript', '.wasm': 'application/wasm', '.ttf': 'font/ttf' };
// (every other path the app's page: a reload at /item/2 loads it there)
const page = `<!doctype html><title>NavWeb</title><body style="margin:0">
<canvas id="c" style="width: 200px; height: 120px; display: block"></canvas>
<script type="module">
import { run } from '/os/browser.mjs';
window.log = [];
window.started = run('/nav.wasm', { imports: ['/os/imports.mjs', '/gfx/imports.mjs', '/text/imports.mjs', '/ui/imports.mjs'], canvas: 'c', gfx: 'webgl2',
	fonts: ['/font.ttf'], stdout: (s) => window.log.push(s), stderr: (s) => window.log.push('stderr: ' + s) });
</script>`;
const server = createServer(async (req, res) => {
	const p = new URL(req.url, 'http://x').pathname;
	try {
		const own = files[p];
		const b = p === '/start' ? Buffer.from('<!doctype html><title>start</title>') : own ? await readFile(own) : Buffer.from(page);
		res.writeHead(200, { 'content-type': own ? types[path.extname(p)] : 'text/html' });
		res.end(b);
	} catch {
		res.writeHead(404);
		res.end();
	}
}).listen(0);
const browser = await pw.chromium.launch({ args: ['--use-angle=swiftshader'] });
let failed = 0;
const check = (what, ok, detail) => {
	if (!ok) failed++;
	console.log(`nav-web.mjs: ${ok ? 'ok' : 'FAIL'}: ${what}${ok ? '' : ': ' + detail}`);
};
try {
	const ctx = await browser.newContext();
	const p = await ctx.newPage();
	const base = `http://localhost:${server.address().port}`;
	const settle = () => p.waitForTimeout(250);
	const at = async () => {
		await settle();
		const l = (await p.evaluate(() => window.log)).filter((s) => s.startsWith('at '));
		return l[l.length - 1];
	};
	const url = () => new URL(p.url()).pathname;
	const back = async () => {
		const cdp = await ctx.newCDPSession(p);
		const { currentIndex, entries } = await cdp.send('Page.getNavigationHistory');
		await cdp.send('Page.navigateToHistoryEntry', { entryId: entries[currentIndex - 1].id });
		await cdp.detach();
	};
	await p.goto(`${base}/start`);
	await p.goto(`${base}/`);
	await p.evaluate(() => window.started);
	check('the root', (await at()) === 'at / 0' && url() === '/', await at());
	const start = await p.evaluate(() => history.length);
	await p.click('#c');
	await p.keyboard.press('n');
	check('a push: its URL, an entry', (await at()) === 'at /item/1 1' && url() === '/item/1' && (await p.evaluate(() => history.length)) === start + 1, `${await at()} ${url()}`);
	await p.keyboard.press('n');
	check('another', (await at()) === 'at /item/2 2' && url() === '/item/2' && (await p.evaluate(() => history.length)) === start + 2, `${await at()} ${url()}`);
	await back();
	check('the history\'s back: popped', (await at()) === 'at /item/1 1' && url() === '/item/1', `${await at()} ${url()}`);
	await p.keyboard.press('Escape');
	check('Escape: popped, the URL following', (await at()) === 'at / 0' && url() === '/', `${await at()} ${url()}`);
	await p.keyboard.press('n');
	await p.keyboard.press('n');
	check('pushed again', (await at()) === 'at /item/4 2' && url() === '/item/4', `${await at()} ${url()}`);
	await p.reload();
	await p.evaluate(() => window.started);
	check('a reload: the screen restored over the root', (await at()) === 'at /item/4 1' && url() === '/item/4', `${await at()} ${url()}`);
	await back();
	check('its back: the root', (await at()) === 'at / 0' && url() === '/', `${await at()} ${url()}`);
	const errors = (await p.evaluate(() => window.log)).filter((s) => s.startsWith('stderr'));
	check('no errors', errors.length === 0, errors.join(' / '));
} finally {
	await browser.close();
	server.close();
}
if (failed > 0) {
	console.log(`nav-web.mjs: ${failed} FAILED`);
	process.exit(1);
}
console.log('nav-web.mjs: ok');
