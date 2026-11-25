// The viewer's startup and navigation against Finder's (macOS; numbers in
// apps/viewer/README.md's How fast). The viewer runs in a home of its own
// (HELDER_HOME: never the user's store, cache or keymap), in the
// background (HELDER_BACKGROUND=1: on screen so its frames present, never
// active), its milestones written by the viewer itself
// (HELDER_VIEWER_TIMING: viewer/Timing.hx, at the frames presented); the
// driver navigates through its single-instance port (Instance: a folder or a
// file handed over, viewer:back, viewer:forward, viewer:close), not through
// the system's input. Finder (finder) is driven by AppleScript, its windows
// read through System Events' accessibility tree until the folder's entries
// are there; it opens windows on the screen and takes the focus, so it runs
// on its own, all at once, its windows closed after.
//   node apps/viewer/tests/bench/finder.mjs viewer [out dir] [--runs n]   (the viewer: apps/viewer/bin/macos-arm64/viewer, built)
//   node apps/viewer/tests/bench/finder.mjs startup [out dir] [--runs n] [--cold]   (a launch's phases alone; VIEWER=<exe>: another build's)
//   node apps/viewer/tests/bench/finder.mjs finder [out dir] [--runs n]   (Finder: on the screen)
//   node apps/viewer/tests/bench/finder.mjs report [out dir]              (the table, from both)
import { spawn, execFileSync } from 'node:child_process';
import { connect } from 'node:net';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const viewerDir = path.join(here, '../..');
const args = process.argv.slice(2);
const what = args[0];
const out = path.resolve(args[1] && !args[1].startsWith('--') ? args[1] : path.join(os.tmpdir(), 'viewer-bench'));
const runs = args.includes('--runs') ? +args[args.indexOf('--runs') + 1] : 10;
const now = () => performance.timeOrigin + performance.now();
const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));
fs.mkdirSync(out, { recursive: true });

// --- the folders and files, made once in out/fixtures
const fx = path.join(out, 'fixtures');
const F = { f10: path.join(fx, 'ten'), f350: path.join(fx, 'downloads'), f10k: path.join(fx, 'ten-thousand'), images: path.join(fx, 'photos'), files: path.join(fx, 'files') };
function fixtures() {
	if (fs.existsSync(path.join(fx, '.made-4'))) return;
	fs.rmSync(fx, { recursive: true, force: true });
	for (const d of Object.values(F)) fs.mkdirSync(d, { recursive: true });
	const samples = path.join(viewerDir, 'samples');
	const jpegs = fs.readdirSync(samples).filter((f) => f.endsWith('.jpg')).map((f) => path.join(samples, f));
	const pdf = path.join(samples, 'About Viewer.pdf');
	const text = (n) => 'x'.repeat(n);
	// (ten: a few of each kind)
	for (let i = 0; i < 4; i++) fs.writeFileSync(path.join(F.f10, `note ${i + 1}.txt`), text(200));
	for (let i = 0; i < 3; i++) fs.copyFileSync(jpegs[i % jpegs.length], path.join(F.f10, `photo ${i + 1}.jpg`));
	fs.copyFileSync(pdf, path.join(F.f10, 'manual.pdf'));
	for (let i = 0; i < 2; i++) fs.mkdirSync(path.join(F.f10, `folder ${i + 1}`));
	// (350, as a Downloads: documents, archives, installers, some pictures, folders)
	const kinds = ['pdf', 'zip', 'dmg', 'txt', 'csv', 'docx', 'md', 'json'];
	for (let i = 0; i < 300; i++) {
		const k = kinds[i % kinds.length], p = path.join(F.f350, `download ${String(i).padStart(3, '0')}.${k}`);
		if (k === 'pdf') fs.copyFileSync(pdf, p);
		else fs.writeFileSync(p, text(1000 + (i * 37) % 9000));
	}
	for (let i = 0; i < 40; i++) fs.copyFileSync(jpegs[i % jpegs.length], path.join(F.f350, `IMG_${1000 + i}.jpg`));
	for (let i = 0; i < 10; i++) fs.mkdirSync(path.join(F.f350, `unpacked ${i}`));
	// (10,000 small files)
	for (let i = 0; i < 10000; i++) fs.writeFileSync(path.join(F.f10k, `item ${String(i).padStart(5, '0')}.txt`), 'x');
	// (200 photos: the samples', each its own file, each a thumbnail of its own)
	for (let i = 0; i < 200; i++) fs.copyFileSync(jpegs[i % jpegs.length], path.join(F.images, `DSC_${String(i).padStart(4, '0')}.jpg`));
	// (opened full size: a JPEG of about 4 MB (24 MP), a HEIC, a PDF; made by sips from a sample)
	const big = path.join(F.files, 'large.jpg');
	execFileSync('sips', ['-z', '4000', '6000', '-s', 'formatOptions', '95', jpegs[0], '--out', big], { stdio: 'ignore' });
	execFileSync('sips', ['-s', 'format', 'heic', big, '--out', path.join(F.files, 'photo.heic')], { stdio: 'ignore' });
	fs.copyFileSync(pdf, path.join(F.files, 'document.pdf'));
	// (a copy of each for every run, five apart: an open decodes its file, not
	// what the viewer decoded ahead around the last (its two neighbours each side))
	for (const name of ['large.jpg', 'photo.heic', 'document.pdf']) for (let k = 0; k < 5 * 10; k++) {
		const [base, ext] = name.split('.');
		fs.copyFileSync(path.join(F.files, name), path.join(F.files, `${base}-${String(k).padStart(3, '0')}.${ext}`));
	}
	fs.writeFileSync(path.join(fx, '.made-4'), '');
}

const stats = (xs) => {
	const s = xs.filter((x) => Number.isFinite(x)).sort((a, b) => a - b);
	if (!s.length) return { median: null, p90: null, n: 0 };
	const q = (k) => s[Math.min(s.length - 1, Math.floor(k * s.length))];
	return { median: +q(0.5).toFixed(1), p90: +q(0.9).toFixed(1), n: s.length };
};

// --- the viewer
// (VIEWER: another build's, a before's)
const exe = process.env.VIEWER ?? path.join(viewerDir, 'bin/macos-arm64/viewer');
const home = path.join(out, 'home'), log = path.join(out, 'timing.log');
const env = { ...process.env, HELDER_HOME: home, HELDER_BACKGROUND: '1', HELDER_VIEWER_TIMING: log };

// the milestones written since offset: [time, frame, what, rest]
function marks(from = 0) {
	const t = fs.existsSync(log) ? fs.readFileSync(log, 'utf8').slice(from) : '';
	return t.split('\n').filter(Boolean).map((l) => {
		const [ms, frame, kind, ...rest] = l.split(' ');
		return { t: +ms, frame: +frame, kind, rest: rest.join(' ') };
	});
}
const size = () => (fs.existsSync(log) ? fs.statSync(log).size : 0);
async function until(from, test, ms = 20000) {
	const t0 = Date.now();
	while (Date.now() - t0 < ms) {
		const m = marks(from), hit = test(m);
		if (hit) return m;
		await sleep(5);
	}
	throw new Error('timed out waiting: ' + JSON.stringify(marks(from).slice(-5)));
}
const after = (m, kind, from = 0) => m.find((x, i) => i >= from && x.kind === kind);

let proc = null;
const instance = path.join(home, 'data/helder-viewer-instance/store.json');
function launch(dir) {
	fs.rmSync(path.dirname(instance), { recursive: true, force: true });
	const at = now();
	proc = spawn(exe, [dir], { env, stdio: 'ignore' });
	return at;
}
// (its port and token, once it has written them)
async function served() {
	for (let k = 0; k < 400; k++) {
		try {
			const s = JSON.parse(fs.readFileSync(instance, 'utf8'));
			if (s.port && s.token) return s;
		} catch {}
		await sleep(25);
	}
	throw new Error('the viewer did not serve its port');
}
async function quit() {
	if (!proc) return;
	const p = proc;
	proc = null;
	p.kill('SIGTERM');
	await new Promise((ok) => (p.exitCode !== null ? ok() : p.once('exit', ok)));
}
// (a path or command handed to the running viewer)
async function send(line) {
	const store = await served();
	await new Promise((ok, fail) => {
		const s = connect(+store.port, '127.0.0.1', () => s.write(`open ${store.token} ${line}\n`));
		s.on('data', () => s.end());
		s.on('close', ok);
		s.on('error', fail);
	});
}

// a folder's milestones after its go: rows, all, thumbs (ms after go), and the listing's batches
function folder(m, dir) {
	const i = m.findIndex((x) => x.kind === 'go' && x.rest === dir);
	if (i < 0) return null;
	const go = m[i], at = (k) => after(m, k, i)?.t - go.t;
	const batches = m.slice(i).filter((x) => x.kind === 'batch');
	const read = batches.find((b) => b.rest.includes('done'));
	return { rows: at('rows'), all: at('all'), thumbs: at('thumbs'), firstBatch: batches[0] ? batches[0].t - go.t : null, read: read ? read.t - go.t : null,
		merge: batches.reduce((s, b) => s + +(/merged in ([\d.]+)/.exec(b.rest)?.[1] ?? 0), 0), frames: (after(m, 'thumbs', i)?.frame ?? go.frame) - go.frame };
}

async function viewer() {
	if (!fs.existsSync(exe)) throw new Error('no viewer: nice -n 20 bun run helder build apps/viewer');
	fixtures();
	fs.rmSync(home, { recursive: true, force: true });
	const r = { startup: { cold: [], warm: [] }, nav: {}, back: [], forward: [], open: {} };
	// startup: launch → the first frame (window), → its folder's rows, → all, → thumbnails; cold: the thumbnails' cache emptied
	for (const kind of ['cold', 'warm']) for (let k = 0; k < runs; k++) {
		if (kind === 'cold') fs.rmSync(path.join(home, 'cache'), { recursive: true, force: true });
		const from = size(), at = launch(F.f350);
		const m = await until(from, (m) => m.some((x) => x.kind === 'thumbs'));
		// (the marks' clock has no epoch: start's line gives it, Date's ms)
		const start = after(m, 'start'), epoch = (t) => t - start.t + +start.rest, go = epoch(m.find((x) => x.kind === 'go').t) - at;
		const f = folder(m, F.f350);
		r.startup[kind].push({ main: +start.rest - at, window: epoch(after(m, 'window').t) - at, rows: go + f.rows, all: go + f.all, thumbs: go + f.thumbs });
		await quit();
		// (a warm launch: the one after a cold one's cache, and the system's file cache, made)
		if (kind === 'warm' && k === 0) r.startup.warm.pop();
	}
	// navigation in one viewer: each folder after another, repeated
	const order = ['f10', 'f350', 'f10k', 'images'];
	launch(F.files);
	await until(0, (m) => m.some((x) => x.kind === 'all'));
	for (const k of order) r.nav[k] = [];
	for (let k = 0; k <= runs; k++) for (const key of order) {
		const from = size();
		await send(F[key]);
		const m = await until(from, (m) => m.some((x) => x.kind === 'thumbs'), 60000);
		// (the first round: thumbnails made, not yet in the cache)
		if (k > 0) r.nav[key].push(folder(m, F[key]));
		else r.nav[key + '-cold'] = [folder(m, F[key])];
	}
	// back and forward between two visited folders
	for (const dir of [F.f350, F.images]) {
		const from = size();
		await send(dir);
		await until(from, (m) => m.some((x) => x.kind === 'thumbs'));
	}
	for (let k = 0; k < runs; k++) for (const dir of ['back', 'forward']) {
		const from = size();
		await send('viewer:' + dir);
		const to = dir === 'back' ? F.f350 : F.images;
		const m = await until(from, (m) => m.some((x) => x.kind === 'thumbs'));
		r[dir].push(folder(m, to));
	}
	// a file full size: asked → its first frame shown (closed between)
	for (const name of ['large.jpg', 'photo.heic', 'document.pdf']) {
		r.open[name] = [];
		for (let k = 0; k < runs; k++) {
			const [base, ext] = name.split('.'), from = size(), p = path.join(F.files, `${base}-${String(5 * k).padStart(3, '0')}.${ext}`);
			await send(p);
			const m = await until(from, (m) => m.some((x) => x.kind === 'image'));
			r.open[name].push(after(m, 'image').t - after(m, 'open').t);
			await send('viewer:close');
			await sleep(400);
		}
	}
	await quit();
	r.sizes = { large: fs.statSync(path.join(F.files, 'large.jpg')).size, heic: fs.statSync(path.join(F.files, 'photo.heic')).size };
	r.load = os.loadavg();
	fs.writeFileSync(path.join(out, 'viewer.json'), JSON.stringify(r, null, 1));
	console.log(summary(r));
}

function summary(r) {
	const lines = [];
	const row = (name, xs, key) => {
		const s = stats(xs.map((x) => (key ? x?.[key] : x)));
		lines.push(`${name.padEnd(34)} median ${String(s.median).padStart(7)} ms   p90 ${String(s.p90).padStart(7)} ms   (${s.n})`);
	};
	for (const kind of ['cold', 'warm']) for (const k of ['main', 'window', 'rows', 'all', 'thumbs']) row(`startup ${kind}: ${k}`, r.startup[kind], k);
	for (const [key, xs] of Object.entries(r.nav)) for (const k of ['firstBatch', 'read', 'merge', 'rows', 'all', 'thumbs']) row(`go ${key}: ${k}`, xs, k);
	for (const dir of ['back', 'forward']) for (const k of ['rows', 'all', 'thumbs']) row(`${dir}: ${k}`, r[dir], k);
	for (const [name, xs] of Object.entries(r.open)) row(`open ${name}`, xs);
	return lines.join('\n');
}

// a launch's phases alone, warm (the second launch on; --cold: each with the
// home's cache emptied, the thumbnails' and the fonts' found): spawn → main, → the
// window asked for (run), → made, → its first frame, → the folder's rows, →
// thumbnails; the listing read (batch done), all in ms after the spawn
async function startup() {
	if (!fs.existsSync(exe)) throw new Error('no viewer: nice -n 20 bun run helder build apps/viewer');
	fixtures();
	const ph = { main: [], run: [], made: [], read: [], window: [], rows: [], thumbs: [] };
	const cold = args.includes('--cold');
	for (let k = 0; k <= runs; k++) {
		if (cold) fs.rmSync(path.join(home, 'cache'), { recursive: true, force: true });
		const from = size(), at = launch(F.f350);
		const m = await until(from, (m) => m.some((x) => x.kind === 'thumbs'));
		await quit();
		if (k === 0) continue;
		const start = after(m, 'start'), epoch = (x) => (x ? x.t - start.t + +start.rest - at : NaN);
		ph.main.push(+start.rest - at);
		for (const kind of ['run', 'made', 'window', 'rows', 'thumbs']) ph[kind].push(epoch(after(m, kind)));
		ph.read.push(epoch(m.find((x) => x.kind === 'batch' && x.rest.includes('done'))));
	}
	const line = Object.entries(ph).map(([k, v]) => `${k} ${stats(v).median}/${stats(v).p90}`).join('  ');
	console.log(`startup (${cold ? 'cold' : 'warm'}, ${runs} runs, median/p90 ms after the spawn; load ${os.loadavg().map((x) => x.toFixed(1)).join(' ')}): ${line}`);
}

// --- Finder (finder.js: AppleScript's JavaScript, System Events' accessibility tree)
async function finder() {
	fixtures();
	// (the order navigated in, its last folder the first's neighbour: each count its own)
	const folders = { f10: { path: F.f10, entries: 10 }, f350: { path: F.f350, entries: 350 }, f10k: { path: F.f10k, entries: 10000 }, images: { path: F.images, entries: 200 } };
	const t0 = now();
	const r = JSON.parse(execFileSync('osascript', ['-l', 'JavaScript', path.join(here, 'finder.js'), JSON.stringify({ folders, runs })], { encoding: 'utf8', timeout: 180000 }));
	r.seconds = (now() - t0) / 1000;
	r.load = os.loadavg();
	fs.writeFileSync(path.join(out, 'finder.json'), JSON.stringify(r, null, 1));
	console.log(table(JSON.parse(fs.readFileSync(path.join(out, 'viewer.json'), 'utf8')), r));
}

// the viewer against Finder: scenario, the viewer's median/p90, Finder's, their ratio
function table(v, f) {
	const s = (xs, k) => stats(xs.map((x) => (k ? x?.[k] : x)));
	const cell = (x) => (x.median === null ? 'n/a' : `${x.median} / ${x.p90}`);
	const lines = ['| scenario | viewer median / p90 (ms) | Finder median / p90 (ms) | viewer ÷ Finder |', '|---|---|---|---|'];
	const row = (name, a, b) => lines.push(`| ${name} | ${cell(a)} | ${b ? cell(b) : '—'} | ${b && a.median && b.median ? (a.median / b.median).toFixed(2) : '—'} |`);
	const names = { f10: '10 entries', f350: '350 entries', f10k: '10,000 entries', images: '200 photos' };
	row('launch → first frame (warm)', s(v.startup.warm, 'window'));
	row('launch → folder\'s rows (warm; Finder: a new window\'s first rows, 350 entries)', s(v.startup.warm, 'rows'), f && s(f.window.f350, 'first'));
	row('launch → folder\'s rows (cold thumbnails)', s(v.startup.cold, 'rows'));
	row('launch → thumbnails (warm)', s(v.startup.warm, 'thumbs'));
	for (const k of Object.keys(names)) {
		row(`go to ${names[k]}: first rows`, s(v.nav[k], 'rows'), f && s(f.nav[k], 'first'));
		row(`go to ${names[k]}: all listed`, s(v.nav[k], 'all'), f && s(f.nav[k], 'all'));
		row(`go to ${names[k]}: thumbnails`, s(v.nav[k], 'thumbs'));
	}
	row('back (350 entries)', s(v.back, 'rows'));
	row('forward (200 photos)', s(v.forward, 'rows'));
	for (const [name, xs] of Object.entries(v.open)) row(`open ${name} full size`, s(xs));
	if (f) {
		lines.push('', `Finder's polling: a count ${cell(stats(f.overhead.count))} ms, the outline found again and counted ${cell(stats(f.overhead.find))} ms (in its times above)`);
		for (const k of Object.keys(names)) lines.push(`Finder, a new window on ${names[k]}: first ${cell(s(f.window[k], 'first'))}, all ${cell(s(f.window[k], 'all'))} ms`);
	}
	return lines.join('\n');
}

if (what === 'viewer') await viewer();
else if (what === 'startup') await startup();
else if (what === 'finder') await finder();
else if (what === 'report') {
	const v = JSON.parse(fs.readFileSync(path.join(out, 'viewer.json'), 'utf8'));
	console.log(summary(v) + '\n');
	const f = fs.existsSync(path.join(out, 'finder.json')) ? JSON.parse(fs.readFileSync(path.join(out, 'finder.json'), 'utf8')) : null;
	console.log(table(v, f));
} else console.log('finder.mjs viewer|finder|report [out dir] [--runs n]');
