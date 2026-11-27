// helder's CSS engine live in a window against helder.ui today and against
// Chromium (bench document): the pages (the HTML Standard as one page, a
// long Wikipedia article: fetched with their stylesheets into
// bin/bench/html; the example's sample page, written by the bench), then
// DocumentBench natively on the app screens and on each page, then
// Chromium (Playwright, headless, the same viewport) on each page, its
// sheets served from the same files and nothing else loaded: the time to
// its first frame after load, and per scroll, hover and resize its main
// thread's style, layout and task time (CDP Performance.getMetrics). The
// tables in bin/document-bench/results.md, the JSON lines beside.
//
//   node tests/bench/document.mjs bin/bench/DocumentBench
import fs from 'node:fs';
import { execFileSync, spawn } from 'node:child_process';
import { playwright } from '../playwright.mjs';

const [bench] = process.argv.slice(2);
const RUNS = Number(process.env.RUNS ?? 3);
const dir = 'bin/bench/html', out = 'bin/document-bench';
fs.mkdirSync(dir, { recursive: true });
fs.mkdirSync(out, { recursive: true });

async function fetchTo(url, file) {
	if (fs.existsSync(file)) return;
	const res = await fetch(url, { headers: { 'user-agent': 'helder-bench' } });
	if (!res.ok) throw new Error(`${url}: ${res.status}`);
	fs.writeFileSync(file, Buffer.from(await res.arrayBuffer()));
}

// (a page and its <link rel=stylesheet>s: URL to file, as the engine resolves them)
async function page(name, url) {
	const file = `${dir}/${name}.html`;
	await fetchTo(url, file);
	const sheets = {};
	const html = fs.readFileSync(file, 'utf8');
	let k = 0;
	for (const m of html.matchAll(/<link\b[^>]*>/g)) {
		const tag = m[0];
		if (!/rel="?stylesheet"?/.test(tag)) continue;
		const href = /href="([^"]+)"/.exec(tag)?.[1]?.replaceAll('&amp;', '&');
		if (!href) continue;
		const abs = new URL(href, url).href;
		const f = `${dir}/${name}-sheet-${k++}.css`;
		await fetchTo(abs, f);
		sheets[abs] = f;
		// (the plain join too: the engine resolves without percent-encoding)
		if (href.startsWith('/')) sheets[new URL(url).origin + href] = f;
	}
	fs.writeFileSync(`${dir}/${name}-sheets.json`, JSON.stringify(sheets, null, 2));
	return { name, url, file, sheets: `${dir}/${name}-sheets.json` };
}

const pages = [await page('html-spec', 'https://html.spec.whatwg.org/'), await page('wikipedia', 'https://en.wikipedia.org/wiki/World_War_II')];

const lines = [];
function run(args) {
	const text = execFileSync(bench, args, { encoding: 'utf8', maxBuffer: 1 << 28, env: { ...process.env, HELDER_TEXT_ENGINE: 'helder', RUNS: String(RUNS) } });
	for (const l of text.split('\n')) if (l.startsWith('{')) lines.push({ ...JSON.parse(l), source: 'helder' });
	process.stdout.write(text);
}
run(['sample-files', dir]);
run(['sample']);
for (const p of pages) run(['doc', p.file, p.sheets, p.name]);
if (!process.env.SKIP_APPS) run(['apps']);

// (each screen of 1,020 rows held in a process of its own: its resident memory, read by ps, and its live heap)
async function memory(screen, variant) {
	const p = spawn(bench, ['mem', screen, variant], { env: { ...process.env, HELDER_TEXT_ENGINE: 'helder' } });
	let text = '';
	const line = await new Promise((done, fail) => {
		p.stdout.on('data', d => {
			text += d;
			const l = text.split('\n').find(x => x.startsWith('{'));
			if (l) done(l);
		});
		p.on('exit', c => fail(new Error(`mem ${screen} ${variant}: exit ${c}`)));
	});
	const rss = Number(execFileSync('ps', ['-o', 'rss=', '-p', String(p.pid)], { encoding: 'utf8' }).trim()) * 1024;
	p.stdin.end('\n');
	const o = { ...JSON.parse(line), rss, source: 'helder' };
	lines.push(o);
	console.log(JSON.stringify(o));
}
if (!process.env.SKIP_APPS) for (const s of ['todo', 'mail']) for (const v of ['helder.ui', 'engine']) await memory(s, v);

// ---- Chromium
const { chromium } = playwright();
const browser = await chromium.launch();
const sample = { name: 'sample', url: 'https://example.com/sample.html', file: `${dir}/sample.html`, sheets: null };
for (const p of [sample, ...pages]) {
	const sheets = p.sheets ? JSON.parse(fs.readFileSync(p.sheets, 'utf8')) : {};
	const loads = [];
	let last = null;
	for (let r = 0; r < RUNS; r++) {
		const context = await browser.newContext({ viewport: { width: 1024, height: 768 }, deviceScaleFactor: 1 });
		const tab = await context.newPage();
		await tab.route('**/*', route => {
			const u = route.request().url();
			if (u === p.url) return route.fulfill({ body: fs.readFileSync(p.file), contentType: 'text/html; charset=utf-8' });
			if (sheets[u]) return route.fulfill({ body: fs.readFileSync(sheets[u]), contentType: 'text/css' });
			// (the sample's images, written beside it)
			const local = `${dir}/${u.split('/').pop()}`;
			if (p === sample && u.endsWith('.png') && fs.existsSync(local)) return route.fulfill({ body: fs.readFileSync(local), contentType: 'image/png' });
			return route.abort();
		});
		await tab.goto(p.url, { waitUntil: 'load' });
		const t = await tab.evaluate(() => new Promise(done => requestAnimationFrame(() => requestAnimationFrame(() => {
			const paint = performance.getEntriesByName('first-contentful-paint')[0];
			done({ frame: performance.now(), fcp: paint ? paint.startTime : null, elements: document.getElementsByTagName('*').length, height: document.documentElement.scrollHeight });
		}))));
		loads.push(t);
		if (last) await last.context().close();
		last = tab;
	}
	const tab = last, cdp = await tab.context().newCDPSession(tab);
	await cdp.send('Performance.enable');
	async function metrics() {
		const m = {};
		for (const x of (await cdp.send('Performance.getMetrics')).metrics) m[x.name] = x.value;
		return m;
	}
	const frame = () => tab.evaluate(() => new Promise(done => requestAnimationFrame(() => requestAnimationFrame(done))));
	// (n steps, each a frame; per step: the main thread's style, layout and task ms, and the wall time to the frame)
	async function op(name, n, act) {
		const a = await metrics(), t0 = Date.now();
		for (let i = 0; i < n; i++) {
			await act(i);
			await frame();
		}
		const b = await metrics(), per = k => Math.round((b[k] - a[k]) * 1e6 / n) / 1000;
		const o = { source: 'chromium', screen: p.name, op: name, frames: n, style: per('RecalcStyleDuration'), layout: per('LayoutDuration'), task: per('TaskDuration'), wall: Math.round((Date.now() - t0) / n * 1000) / 1000 };
		lines.push(o);
		console.log(JSON.stringify(o));
	}
	const best = k => Math.min(...loads.map(l => l[k] ?? Infinity));
	const fcp = best('fcp');
	const l = { source: 'chromium', screen: p.name, op: 'load to the first frame', frame: Math.round(best('frame') * 1000) / 1000, fcp: Number.isFinite(fcp) ? fcp : null, elements: loads[0].elements, height: loads[0].height };
	lines.push(l);
	console.log(JSON.stringify(l));
	await op('scroll, 100 px a frame', 300, () => tab.evaluate(() => window.scrollBy(0, 100)));
	await tab.evaluate(() => window.scrollTo(0, 0));
	await frame();
	const links = await tab.evaluate(() => [...document.querySelectorAll('a[href]')].map(a => a.getBoundingClientRect()).filter(r => r.y > 20 && r.y < 728 && r.width > 4).slice(0, 12).map(r => [r.x + 2, r.y + r.height / 2]));
	if (links.length > 0) await op('hover links', 120, i => tab.mouse.move(links[i % links.length][0], links[i % links.length][1]));
	await tab.mouse.move(1019, 763);
	await op('resize 1024 ↔ 900 wide', 20, i => tab.setViewportSize({ width: i % 2 == 0 ? 900 : 1024, height: 768 }));
	await tab.context().close();
}
await browser.close();
fs.writeFileSync(`${out}/results.jsonl`, lines.map(l => JSON.stringify(l)).join('\n') + '\n');

// ---- the tables
const md = [];
const f = v => v == null ? '' : typeof v === 'number' ? (Math.abs(v) >= 100 ? Math.round(v).toLocaleString('en') : v.toFixed(2)) : v;
const kb = v => v == null ? '' : Math.round(v / 1024).toLocaleString('en');
const apps = lines.filter(l => l.op && l.variant && (l.screen === 'todo' || l.screen === 'mail'));
for (const screen of ['todo', 'mail']) {
	const rows = apps.filter(l => l.screen === screen);
	if (rows.length == 0) continue;
	md.push(`\n### ${screen}\n\n| operation | helder.ui: frame ms (median, min) | engine: frame ms (median, min) | engine's own: style + layout + paint | GC KB a frame (ui, engine) |\n| --- | ---: | ---: | ---: | ---: |`);
	for (const op of [...new Set(rows.map(r => r.op))]) {
		const u = rows.find(r => r.op === op && r.variant === 'helder.ui'), e = rows.find(r => r.op === op && r.variant === 'engine');
		md.push(`| ${op} | ${f(u?.median)} (${f(u?.min)}) | ${f(e?.median)} (${f(e?.min)}) | ${f(e?.style)} + ${f(e?.layout)} + ${f(e?.paint)} | ${kb(u?.gcBytes)}, ${kb(e?.gcBytes)} |`);
	}
	const mem = v => lines.find(l => l.memory && l.screen === screen && l.variant === v);
	const mu = mem('helder.ui'), me = mem('engine');
	if (mu && me) md.push(`\n1,020 rows held: helder.ui ${kb(mu.heap)} KB live heap, ${kb(mu.rss)} KB resident; the engine ${kb(me.heap)} KB live heap, ${kb(me.rss)} KB resident.`);
}
for (const p of [sample, ...pages]) {
	const h = lines.filter(l => l.source === 'helder' && l.screen === p.name && l.op), c = lines.filter(l => l.source === 'chromium' && l.screen === p.name);
	const info = lines.find(l => l.screen === p.name && l.boxes != null);
	md.push(`\n### ${p.name}${info ? ` (${info.elements.toLocaleString('en')} elements, ${info.boxes.toLocaleString('en')} boxes, ${info.fragments.toLocaleString('en')} fragments, ${info.height.toLocaleString('en')} px tall)` : ''}\n\n| operation | helder: frame ms (median, min) | helder's engine: style + layout + paint | Chromium: main thread task ms | Chromium: style + layout | Chromium: wall ms a step |\n| --- | ---: | ---: | ---: | ---: | ---: |`);
	for (const op of [...new Set(h.map(r => r.op))]) {
		const e = h.find(r => r.op === op), k = c.find(r => r.op === op);
		const chrome = op.startsWith('load') ? `${f(k?.frame)} (FCP ${f(k?.fcp)})` : f(k?.task);
		md.push(`| ${op} | ${f(e?.median)} (${f(e?.min)}) | ${f(e?.style)} + ${f(e?.layout)} + ${f(e?.paint)} | ${chrome} | ${k && !op.startsWith('load') ? `${f(k.style)} + ${f(k.layout)}` : ''} | ${f(k?.wall)} |`);
	}
}
fs.writeFileSync(`${out}/results.md`, md.join('\n') + '\n');
console.log(md.join('\n'));
