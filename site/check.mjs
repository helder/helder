// The site's check (bun run site:check, after bun run site), in headless
// Chromium (Playwright): bin/site served, every example a card on
// examples/, the top bar's links (Examples, Docs, GitHub) on an iPhone's
// screen (Playwright's device: its viewport, scale and touch) on the
// examples' pages, and behind the docs' menu there; then the
// Play button of every demo pressed (or of the ids given): each started (data-hydrated, the
// graphics API it draws with in data-gfx), its canvas drawn (it looks
// different from before once it rendered frames; a sound only started), no console errors. Then
// the docs (bin/site/docs): every page, its sidebar, pictures, language
// tabs and live example (started once in view), the old addresses sent
// on, the search. With a
// directory, the page's screenshots at a phone's width and a desktop's are
// written there.
//
//   node site/check.mjs [screenshots dir] [ids to play...]   (default: every demo)
// SITE_NO_WEBGPU=1: the pages without navigator.gpu (WebGL2's path), as a
// Chromium without WebGPU sees them.
// --shard i/n: every n-th demo and docs page from the i-th (CI's
// check jobs, a machine each: two SwiftShader browsers on one machine's
// cores starved each other's frames); the index's and the search's
// checks on every shard, the phone's on the first.
import { takeShard } from '../tests/shard.mjs';
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dir = path.join(root, 'bin/site');
const args = process.argv.slice(2);
const [shard, shards] = takeShard(args);
const [shots, ...ids] = args;
const site = JSON.parse(fs.readFileSync(path.join(root, 'bin/site-build/examples.json'), 'utf8'));
// (the index's examples: docs/examples' are played in their pages, below)
const listed = site.examples.filter((e) => !e.docs);
const mine = (_, k) => k % shards === shard;
const play = (ids.length ? ids.filter((id) => !site.examples.find((e) => e.id === id)?.docs) : listed.filter((e) => e.demo).map((e) => e.id)).filter(mine);
if (shards > 1) console.log(`site/check.mjs: shard ${shard} of ${shards}: ${play.length} demos`);

const types = { '.css': 'text/css', '.ttf': 'font/ttf', '.mjs': 'text/javascript', '.js': 'text/javascript', '.wasm': 'application/wasm', '.html': 'text/html', '.json': 'application/json' };
const server = createServer(async (req, res) => {
	const p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
	try {
		const b = await readFile(path.join(dir, p.endsWith('/') ? p + 'index.html' : p));
		res.writeHead(200, { 'content-type': types[path.extname(p)] ?? (p.endsWith('/') ? 'text/html' : 'application/octet-stream') });
		res.end(b);
	} catch {
		res.writeHead(404);
		res.end();
	}
}).listen(0);
const url = `http://localhost:${server.address().port}/`;

const browser = await pw.chromium.launch({ args: ['--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-angle=swiftshader'] });
let failures = 0;
const check = (ok, what) => {
	console.log(`${ok ? 'PASS' : 'FAIL'} ${what}`);
	if (!ok) failures++;
};
try {
	const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
	// (SITE_NO_WEBGPU=1: navigator.gpu taken away, as a Chromium without WebGPU)
	if (process.env.SITE_NO_WEBGPU) await page.addInitScript(() => delete Navigator.prototype.gpu);
	const errors = [];
	// (a failed fetch by its URL, not the console's line: the videos and numbers a build without site/reel.mjs or site/numbers.mjs has not)
	const later = ['examples/media/', 'examples/numbers.json'].filter((f) => !fs.existsSync(path.join(dir, f)));
	// (each with the page it came from: the pages are many, one at a time)
	const at = () => page.url().replace(url, '/');
	page.on('console', (m) => m.type() === 'error' && !m.text().startsWith('Failed to load resource') && errors.push(`${at()}: ${m.text()}`));
	page.on('response', (r) => r.status() >= 400 && !later.some((f) => r.url().startsWith(url + f)) && errors.push(`${r.status()} ${r.url()}`));
	page.on('pageerror', (e) => errors.push(`${at()}: ${e}`));
	await page.goto(url + 'examples/');
	const cards = await page.locator('article.card').count();
	check(cards === listed.length, `${cards} cards, ${listed.length} examples`);
	const buttons = await page.locator('button.play').count();
	check(buttons === listed.filter((e) => e.demo).length, `${buttons} Play buttons`);
	for (const e of listed) {
		const card = page.locator(`#${e.id}`);
		const title = await card.locator('h3').textContent();
		if (title !== e.title) check(false, `${e.id}'s title: ${title}`);
	}
	if (shots) {
		await mkdir(shots, { recursive: true });
		await shot(page, 'site-desktop.png');
		await page.setViewportSize({ width: 390, height: 844 });
		await shot(page, 'site-phone.png');
		await shot(page, 'site-phone-full.png', { fullPage: true });
		await page.setViewportSize({ width: 1280, height: 900 });
	}
	// (each demo alone in the page, loaded again: the heavy ones, a million
	// particles on a software GPU, would slow the next ones' checks)
	async function start(id) {
		await page.goto(url + 'examples/');
		const island = page.locator(`#play-${id}`);
		await island.scrollIntoViewIfNeeded();
		await island.locator('button.play').click();
		await page.waitForFunction((id) => document.getElementById('play-' + id).hasAttribute('data-hydrated'), id, { timeout: 60000 });
	}
	for (const id of play) {
		await page.goto(url + 'examples/');
		const island = page.locator(`#play-${id}`), canvas = island.locator('canvas');
		await island.scrollIntoViewIfNeeded();
		// (a sound has no canvas: started, nothing drawn)
		const drawn = (await canvas.count()) > 0;
		const before = drawn ? await canvas.screenshot() : null;
		await island.locator('button.play').click();
		await page.waitForFunction((id) => {
			const el = document.getElementById('play-' + id);
			return el.hasAttribute('data-hydrated') || el.hasAttribute('data-error');
		}, id, { timeout: 60000 });
		const error = await island.getAttribute('data-error'), gfx = await island.getAttribute('data-gfx');
		check(error === null, `${id} started${error ? ': ' + error : ''}`);
		if (!drawn || error !== null) continue;
		check(!!gfx, `${id} draws with ${gfx}`);
		await island.scrollIntoViewIfNeeded();
		// (a frame's colours are no test here: a game may open on a dark screen)
		await renderedFrames(island);
		check(!before.equals(await canvas.screenshot()), `${id}'s canvas drawn`);
		if (shots) {
			await shot(page, `site-desktop-${id}.png`);
			await page.setViewportSize({ width: 390, height: 844 });
			await island.scrollIntoViewIfNeeded();
			await renderedFrames(island);
			await shot(page, `site-phone-${id}.png`);
			await page.setViewportSize({ width: 1280, height: 900 });
		}
		// (an example of fetched data, heavy: stopped once out of view, data-stop="offscreen")
		if (site.examples.find((x) => x.id === id)?.args?.length) {
			await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
			await page.waitForFunction((id) => document.getElementById('play-' + id).hasAttribute('data-stopped'), id, { timeout: 30000 });
			check(true, `${id} stopped out of view`);
		}
	}
	// (a demo full screen and expanded at a phone's size: planets, ui's markup with a <Scene> in it)
	if (play.includes('planets')) {
		await start('planets');
		await phone(page, shots, 'planets');
	}
	await checkDocs(page);
	if (shard === 0) await checkPhone(shots);
	check(errors.length === 0, `no console errors${errors.length ? ': ' + errors.join('\n') : ''}`);
} finally {
	await browser.close();
	server.close();
}
if (failures) process.exit(1);

// the docs: each page of docs/search.json (Docs.hx's, every page) loaded,
// its sidebar listing every page, its pictures loaded, its live example
// started once scrolled to (a sound on its button) and drawn, its
// TypeScript and Haxe tabs switching; the language chosen kept on the next
// page; the old addresses sent on; the search
async function checkDocs(page) {
	const pages = JSON.parse(fs.readFileSync(path.join(dir, 'docs/search.json'), 'utf8'));
	check(pages.length > 0, `${pages.length} docs pages`);
	for (const p of pages.filter(mine)) {
		await page.goto(url + p.url);
		const title = await page.locator('main h1').textContent();
		check(title === p.title, `${p.url}: its title, ${title}`);
		const links = await page.locator('.sidebar ul a').count();
		if (links !== pages.length) check(false, `${p.url}: ${links} pages in its sidebar, of ${pages.length}`);
		// (the pictures of <Image>: a live example's poster is hidden once it draws)
		for (const img of await page.locator('main .still img').all()) {
			await img.scrollIntoViewIfNeeded();
			const decoded = await img.evaluate(i => i.decode().then(() => i.naturalWidth > 0, () => false));
			check(decoded, `${p.url}: ${await img.getAttribute('src')} shown`);
		}
		const langs = page.locator('.langs');
		if (await langs.count()) {
			const box = langs.first();
			await box.locator('.switch button[data-lang="haxe"]').click();
			check(await box.locator('pre[data-lang="haxe"]').isVisible() && await box.locator('pre[data-lang="ts"]').isHidden(), `${p.url}: the Haxe tab shows Haxe`);
			await box.locator('.switch button[data-lang="ts"]').click();
		}
		const islands = page.locator('.example hxmc-island');
		for (let k = 0; k < await islands.count(); k++) {
			const island = islands.nth(k), id = (await island.getAttribute('id')).slice('play-'.length);
			if (ids.length && !ids.includes(id)) continue;
			await island.scrollIntoViewIfNeeded();
			const sound = (await island.locator('canvas').count()) === 0;
			if (sound) await island.locator('button.play').click();
			await page.waitForFunction((id) => {
				const el = document.getElementById('play-' + id);
				return el.hasAttribute('data-hydrated') || el.hasAttribute('data-error');
			}, id, { timeout: 60000 });
			const error = await island.getAttribute('data-error');
			check(error === null, `${p.url}: ${id} started once in view${error ? ': ' + error : ''}`);
			if (sound || error !== null) continue;
			// (started once in view, so there is no frame from before it ran: a frame of more than a few colours is drawn)
			const colours = await renderedFrames(island);
			check(colours > 8, `${p.url}: ${id}'s canvas drawn (${colours} colours)`);
			if (shots) await shot(page, `docs-${id}.png`);
		}
	}
	// (Haxe chosen on one page: the next page's samples open in Haxe)
	await page.goto(url + 'docs/apps/views/');
	await page.locator('.langs .switch button[data-lang="haxe"]').first().click();
	await page.goto(url + 'docs/apps/lists/');
	check(await page.locator('.langs pre[data-lang="haxe"]').first().isVisible(), 'the language chosen is kept on the next page');
	await page.evaluate(() => localStorage.removeItem('helder.lang'));
	await page.goto(url + 'docs/guide/start/');
	await page.waitForURL(/docs\/start\/install\/$/, { timeout: 10000 });
	check(page.url().endsWith('docs/start/install/'), 'an old address sends on to its page');
	await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
	const first = page.locator('main .code').first();
	await first.hover();
	await first.getByRole('button', {name: 'Copy code'}).click();
	check(await page.evaluate(() => navigator.clipboard.readText()) === await first.locator('pre:not([hidden]) code').textContent(), 'Copy copies the sample shown');
	// (the search: a word of a page's heading finds it)
	await page.goto(url + pages[1].url);
	await page.locator('.search').fill('bloom');
	await page.waitForSelector('.results:not([hidden]) a', { timeout: 10000 });
	const hit = await page.locator('.results a').first().getAttribute('href');
	check(hit.startsWith('docs/'), `the search finds "bloom": ${hit}`);
	await page.locator('.search').press('ArrowDown');
	check(await page.locator('.results a').first().evaluate(a => a === document.activeElement), 'ArrowDown focuses the first result');
	await page.keyboard.press('Escape');
	check(await page.locator('.results').isHidden() && await page.locator('.search').evaluate(input => input === document.activeElement),
		'Escape closes results and returns focus to search');
}

// a screenshot for the artifacts, not a check: one that times out (a heavy
// demo starving SwiftShader's frames) is noted and the check goes on
async function shot(page, name, options = {}) {
	try {
		await page.screenshot({ path: path.join(shots, name), ...options });
	} catch (e) {
		console.log(`site/check.mjs: no screenshot ${name}: ${e.message.split('\n')[0]}`);
	}
}

// Readback resolves once a canvas frame has rendered, including in a worker.
// Request each frame separately so an idle scene redraws and a slow GPU can catch up.
async function renderedFrames(island) {
	return island.evaluate(async (el) => {
		const { host } = await globalThis.hxmcWasm[el.id];
		let timer;
		try {
			return await Promise.race([
				(async () => {
					let pixels;
					for (let n = 0; n < 3; n++) {
						const frame = host.gfx.readPixels();
						host.os.redraw();
						pixels = await frame;
					}
					// Let the browser composite the canvas before Playwright captures it.
					await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
					const { data, width, height } = pixels;
					const colours = new Set();
					for (let y = 0; y < height; y += 4) for (let x = 0; x < width; x += 4) {
						const i = (y * width + x) * 4;
						colours.add((data[i] << 16) | (data[i + 1] << 8) | data[i + 2]);
					}
					return colours.size;
				})(),
				new Promise((_, reject) => {
					timer = setTimeout(() => reject(new Error(`${el.id}: timed out waiting for three rendered frames`)), 60000);
				}),
			]);
		} finally {
			clearTimeout(timer);
		}
	});
}

// on an iPhone (Playwright's iPhone 13: 390x844 at 3x, touch, its user
// agent; a window's size alone lays the page out otherwise): the examples'
// pages show the top bar's links; a docs page hides them, its menu (☰)
// opening the pages with the site's links over it
async function checkPhone(shots) {
	const context = await browser.newContext({ ...pw.devices['iPhone 13'] });
	const page = await context.newPage();
	const visible = (sel) => page.locator(sel).evaluateAll((els) => els.filter((e) => e.offsetParent !== null && e.getBoundingClientRect().right <= innerWidth + 1)
		.map((e) => e.textContent.trim()));
	const paged = listed.find((e) => e.page);
	for (const [name, at] of [['examples', 'examples/'], ...(paged ? [['example', `examples/${paged.id}/`]] : [])]) {
		await page.goto(url + at);
		const links = await visible('.top nav a');
		check(['Examples', 'Docs', 'GitHub'].every((l) => links.includes(l)), `phone, ${at}: the top bar's links (${links.join(', ')})`);
		check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `phone, ${at}: no sideways scroll`);
		if (shots) await shot(page, `phone-${name}.png`);
	}
	const docs = JSON.parse(fs.readFileSync(path.join(dir, 'docs/search.json'), 'utf8'));
	await page.goto(url + docs[1].url);
	check((await visible('.top nav a')).length === 0, `phone, ${docs[1].url}: the top bar's links hidden`);
	check(await page.locator('.menu').isVisible(), `phone, ${docs[1].url}: the menu shown`);
	check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `phone, ${docs[1].url}: no sideways scroll`);
	if (shots) await shot(page, 'phone-docs.png');
	await page.locator('.menu').tap();
	const inMenu = await visible('.sidebar .links a');
	check(['Examples', 'GitHub'].every((l) => inMenu.includes(l)) && (await page.locator('.sidebar ul a').first().isVisible()),
		`phone, ${docs[1].url}: the menu holds the site's links (${inMenu.join(', ')}) and the pages`);
	if (shots) await shot(page, 'phone-docs-menu.png');
	await context.close();
}

// a demo at 390x844: full screen (the Fullscreen API) then expanded (as on
// an iPhone, without element full screen): the canvas filling the screen
// at the device's pixels, its touches the demo's (touch-action none), the
// page not scrolled; screenshots of both when asked
async function phone(page, shots, id) {
	await page.setViewportSize({ width: 390, height: 844 });
	const stage = page.locator(`#${id} .stage`), canvas = page.locator(`#play-${id} canvas`);
	await stage.scrollIntoViewIfNeeded();
	await page.locator(`#${id} button.full`).click();
	await page.waitForTimeout(1500);
	const full = await page.evaluate((id) => {
		const c = document.querySelector(`#play-${id} canvas`), s = document.querySelector(`#${id} .stage`);
		return { el: document.fullscreenElement === s, w: c.clientWidth, h: c.clientHeight, bw: c.width, bh: c.height, dpr: devicePixelRatio };
	}, id);
	check(full.el && full.w === 390 && full.h === 844, `${id} full screen: the stage the full screen element, its canvas ${full.w}x${full.h}`);
	check(full.bw === Math.round(full.w * full.dpr) && full.bh === Math.round(full.h * full.dpr), `${id} full screen: the canvas's buffer ${full.bw}x${full.bh} (its size times ${full.dpr})`);
	if (shots) await shot(page, `${id}-fullscreen.png`);
	await page.locator(`#${id} button.exit`).click();
	await page.waitForTimeout(800);
	check(await page.evaluate((id) => !document.fullscreenElement && !document.querySelector(`#${id} .stage.expanded`), id), `${id} full screen: left by Exit`);
	// (as on an iPhone: no element full screen, so expanded over the page)
	await page.evaluate(() => {
		for (const k of ['fullscreenEnabled', 'webkitFullscreenEnabled']) Object.defineProperty(document, k, { get: () => false, configurable: true });
	});
	await page.locator(`#${id} button.full`).click();
	await page.waitForTimeout(1500);
	const box = await canvas.boundingBox();
	const ex = await page.evaluate((id) => {
		const c = document.querySelector(`#play-${id} canvas`);
		return { expanded: !!document.querySelector(`#${id} .stage.expanded`), full: !!document.fullscreenElement, touch: getComputedStyle(c).touchAction, scroll: scrollY };
	}, id);
	check(ex.expanded && !ex.full && Math.round(box.width) === 390 && Math.round(box.height) === 844, `${id} expanded: over the viewport, ${Math.round(box.width)}x${Math.round(box.height)}`);
	check(ex.touch === 'none', `${id} expanded: the canvas's touch-action ${ex.touch}`);
	// (a finger dragged over it: the demo's, the page not scrolled; the DevTools protocol's touches)
	const cdp = await page.context().newCDPSession(page);
	const at = (x, y) => [{ x, y, id: 1, radiusX: 4, radiusY: 4, force: 1 }];
	const x = box.x + box.width / 2, y0 = box.y + box.height / 2;
	await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: at(x, y0) });
	for (let i = 1; i <= 12; i++) {
		await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: at(x, y0 + i * 9) });
		await page.waitForTimeout(25);
	}
	await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
	await page.waitForTimeout(500);
	check(await page.evaluate(() => scrollY) === ex.scroll, `${id} expanded: a touch drag did not scroll the page`);
	if (shots) await shot(page, `${id}-expanded.png`);
	await page.locator(`#${id} button.exit`).click();
	await page.waitForTimeout(500);
	check(await page.evaluate((id) => !document.querySelector(`#${id} .stage.expanded`) && !document.documentElement.classList.contains('playing'), id), `${id} expanded: left by Exit`);
	await page.setViewportSize({ width: 1280, height: 900 });
}
