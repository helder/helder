// helder.ui's ARIA mirror in a browser (bun run test ui-web): WebAccessPage.wasm
// (AccessFixture's controls) in headless Chromium, the page's accessibility
// tree read as assistive technology reads it: Chromium's own tree through
// the DevTools protocol (roles, names and states as Chromium computes them:
// Playwright's ARIA snapshot leaves out a canvas's fallback content), with
// the mirror's ARIA counts and indices (a grid's rows and columns, a cell's
// place, a list item's place in its set, which the protocol does not
// give); then the mirror's
// elements clicked as a screen reader clicks them (a disclosure expanded, a
// row selected, the Save button), the program's state and the tree after.
// With worker, the program in a worker (browser.mjs's option worker).
//   node tests/ui/web-access.mjs <WebAccessPage.wasm> [worker]
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
const files = {
	'/access.wasm': wasm,
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
const page = `<!doctype html><title>Access</title><body style="margin:0">
<canvas id="c" style="width: 400px; height: 640px; display: block"></canvas>
<script type="module">
import { run } from './os/browser.mjs';
window.log = [];
window.start = async (worker) => {
	window.r = run('access.wasm', { imports: ['os/imports.mjs', 'gfx/imports.mjs', 'text/imports.mjs', 'ui/imports.mjs'], canvas: 'c', gfx: 'webgl2', worker,
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
const browser = await pw.chromium.launch({ args: ['--use-angle=swiftshader', '--force-renderer-accessibility'] });
const p = await browser.newPage({ viewport: { width: 420, height: 660 } });
const errors = [];
p.on('pageerror', (e) => errors.push(e.message));
p.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
let failed = 0, checks = 0;
const check = (what, ok, detail) => {
	checks++;
	if (!ok) {
		failed++;
		console.log(`web-access.mjs${mode}: FAIL: ${what}${detail === undefined ? '' : ': ' + detail}`);
	}
};
try {
	await p.goto(url);
	await p.evaluate((w) => window.start(w), worker);
	await p.waitForFunction(() => window.log.some((l) => l.startsWith('state ')), null, { timeout: 20000 });
	const state = async () => (await p.evaluate(() => window.log)).filter((l) => l.startsWith('state ')).pop();
	// (each step's outcome waited for, not a fixed 300 ms: in a worker a
	// click goes to the program and the tree comes back by messages, later
	// on a busy machine; f's last value once truthy, or once 10 s passed;
	// how long each took, printed)
	const waited = [];
	const until = async (f, ms = 10000) => {
		const t0 = Date.now();
		let v = await f();
		while (!v && Date.now() - t0 < ms) {
			await p.waitForTimeout(50);
			v = await f();
		}
		waited.push(Date.now() - t0);
		return v;
	};
	// Chromium's accessibility tree (what a screen reader gets; Playwright's
	// ARIA snapshot leaves the canvas's fallback content out, having no
	// boxes): each node as role "name" [states]
	const cdp = await p.context().newCDPSession(p);
	const snapshot = async () => {
		const ax = (await cdp.send('Accessibility.getFullAXTree')).nodes.filter((n) => !n.ignored);
		const lines = ax.map((n) => {
			const states = (n.properties ?? []).filter((x) => ['expanded', 'selected', 'checked', 'readonly', 'disabled'].includes(x.name))
				.map((x) => `[${x.name}=${x.value.value}]`).join(' ');
			return `${n.role?.value} "${n.name?.value ?? ''}"${states ? ' ' + states : ''}`;
		});
		return { ax, text: lines.join('\n') };
	};
	const wants = ['button "Save"', 'checkbox "Remember" [checked=false]', 'slider "Volume"', 'textbox "Name"', 'textbox "Code" [readonly=true]', 'textbox "Notes"',
		'button "More" [expanded=false]', 'list "Fruits"', 'listitem "Pear"', 'grid "Mail"', 'row "Bob Lunch" [selected=false]', 'gridcell "Lunch"',
		'columnheader "Subject"', 'tablist ""', 'tab "General" [selected=true]', 'StaticText "Ready"'];
	const has = (text, want) => text.split('\n').some((l) => l.startsWith(want));
	// (the tree once the mirror has all of it, else the last read)
	let first;
	await until(async () => {
		first = await snapshot();
		return wants.every((want) => has(first.text, want));
	});
	for (const want of wants)
		check(`the tree: ${want}`, has(first.text, want), want);
	if (failed) console.log(first.text);
	const prop = (n, k) => n?.properties?.find((x) => x.name === k)?.value?.value;
	// a screen reader's clicks on the mirror's elements
	const click = (role, name) => until(() => p.evaluate(([r, n]) => {
		const e = [...document.querySelectorAll(`#c [role=${r}]`)].find((x) => x.getAttribute('aria-label') === n);
		if (!e) return false;
		e.click();
		return true;
	}, [role, name]));
	// (the program's state once it has s, else its last)
	const stated = async (s) => (await until(async () => (await state()).includes(s))) ? await state() : `${await state()} (no ${s} in 10 s)`;
	check('More clicked', await click('button', 'More'));
	const open = await stated('open=true');
	check('expanded: the program', open.includes('open=true') && !open.includes(' (no '), open);
	let after;
	await until(async () => (after = (await snapshot()).text).includes('button "More" [expanded=true]') && after.includes('StaticText "Extra"'));
	check('expanded: the tree', after.includes('button "More" [expanded=true]') && after.includes('StaticText "Extra"'), after);
	check('a row clicked', await click('row', 'Bob Lunch'));
	const row = await stated('row=1');
	check('selected: the program', !row.includes(' (no '), row);
	const bob = await until(async () => {
		const ax = (await cdp.send('Accessibility.getFullAXTree')).nodes.filter((n) => !n.ignored);
		const n = ax.find((n) => n.role?.value === 'row' && n.name?.value === 'Bob Lunch');
		return prop(n, 'selected') === true ? n : null;
	});
	check('selected: the tree', bob != null);
	check('Save clicked', await click('button', 'Save'));
	const saved = await stated('saved=1');
	check('saved', !saved.includes(' (no '), saved);
	check('no page errors', errors.length === 0, errors.join(' | '));
	console.log(`web-access.mjs${mode}: waited (ms) for the tree, More's click, the program, the tree, the row's click, the program, the tree, Save's click, the program: ${waited.join(' ')}`);
} catch (e) {
	failed++;
	console.log('web-access.mjs: FAIL: ' + e.message);
}
console.log(`web-access.mjs${mode}: ${checks} checks` + (failed ? `, ${failed} FAILED` : ', ok'));
await browser.close();
server.close();
process.exit(failed ? 1 : 0);
