// The site (bun run site): the examples' pages and the docs, laid out to
// be served from a site's root (helder.build's: its assemble.mjs builds this
// with its theme):
//
//   examples/            the examples' page (site/index.tsx: TSX through
//                        helder's TypeScript frontend, rendered by
//                        helder.web's static renderer), each example that
//                        runs in a browser a WebAssembly island started by
//                        its Play button
//   examples/<id>/       its module, assets and data; index.html for an
//                        example with a page.json (its demo, description,
//                        the numbers' slots: site/numbers.mjs measures them
//                        into examples/numbers.json, which the page reads;
//                        real devices', three.js' for the same scene, credits)
//   examples/media/      the videos site/reel.mjs records (not built here:
//                        stage.js shows a note where one is missing)
//   examples/apk/        SITE_APK=1: the `// apk: android` examples' APKs
//   docs/                site/docs/Docs.hx's pages from docs/ (docs/examples'
//                        builds among the examples', not on the index:
//                        CONTRIBUTING.md, "Docs")
//   static/              the pages' sheet, scripts and fonts, the packages'
//                        browser modules (all the builds' together)
//   index.html           (to examples/, for a local server)
//
//   node site/build.mjs [out]      (default bin/site)
//
// 1. the examples: each directory's programs with a header (as tests/Run.hx's
//    examples lane reads them: `// title:`, `// summary:`, `// tags:`,
//    `// demo:`), a .hx file or a TypeScript directory's main.ts(x);
// 2. those whose demo is `canvas WxH` or `sound` built for the web
//    (`helder build <entry> --target web`, one build each), into
//    bin/site-build/<id>/, then laid out as above;
// 3. bin/site-build/examples.json (their headers and builds, the clips, the
//    theme), which index.tsx imports and Docs.hx reads; both built natively
//    and run.
//
// SITE_THEME=<file.json>: a host's theme over the default one (THEME below):
// the brand and its link, the top bar's links and button, a notice line,
// sheets and scripts after static/site.css, the footer's links, starters
// (cards above the examples). Links are relative to the site's root (each
// page's <base>) or absolute.
//
// `// data: <folder>`: files the example fetches at run time, not bundled
// (tens of MB of models): its fetch.mjs run first (downloading them into
// examples/<dir>/<folder>), the folder copied beside its module and its
// URL (relative to the pages) passed as the program's first argument.
// SITE_SKIP_DATA=1: those not built (listed, no Play button): a quick
// local build, or one where their fetch.mjs cannot run (Windows).
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { CLIPS } from './reel.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
process.chdir(root);
const out = process.argv[2] ?? 'bin/site';
const work = 'bin/site-build';
const cli = ['src/helder/cli/run.mjs'];
const REPO = 'https://github.com/helder/helder';
const THEME = {
	brand: 'helder', home: 'examples/',
	nav: [{ id: 'examples', label: 'Examples', href: 'examples/' }, { id: 'docs', label: 'Docs', href: 'docs/' }, { id: '', label: 'GitHub', href: REPO }],
	action: { id: '', label: '', href: '' }, css: [], js: [], notice: '', footer: [], starters: { title: '', lede: '', items: [] }
};
const theme = { ...THEME, ...(process.env.SITE_THEME ? JSON.parse(fs.readFileSync(process.env.SITE_THEME, 'utf8')) : {}) };
theme.action = { ...THEME.action, ...theme.action };
theme.starters = { ...THEME.starters, ...theme.starters };
theme.starters.items = theme.starters.items.map((s) => ({ summary: '', image: '', width: 0, height: 0, kind: '', ...s }));
for (const l of [...theme.nav, ...theme.footer]) l.id ??= '';

// (apk: android, an example built for Android phones too, with SITE_APK=1: its APK beside the page, linked from its card)
const HEADER = /^\/\/ *(title|summary|tags|demo|apk|data): *(.*)$/;

function header(file) {
	const head = {};
	for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
		if (!line.startsWith('//')) break;
		const m = HEADER.exec(line.trim());
		if (m) head[m[1]] = m[2].trim();
	}
	return head.title ? head : null;
}

// demo: canvas WxH (a canvas of that size; then 1x: a pixel a point, not
// multisampled, as PixiJS's Bunnymark is drawn), sound (no canvas: a click
// starts the audio); island and module are helder.web's, not a program to start
function demoOf(s) {
	const c = /^canvas (\d+)x(\d+)( 1x)?$/.exec(s ?? '');
	if (c) return { kind: 'canvas', width: +c[1], height: +c[2], onePixel: !!c[3] };
	if (s === 'sound') return { kind: 'sound', width: 0, height: 0, onePixel: false };
	return null;
}

// the examples, by directory (their ids as tests/Run.hx's examples lane names them);
// then docs/examples' (the docs' own, not on the index: docs: true), a
// directory's Haxe program its entry and its main.ts, when it has one, its
// TypeScript twin (alt: shown beside it in the docs, built by the examples lane)
function examples() {
	const list = [];
	for (const root of ['examples', 'docs/examples']) {
		const docs = root !== 'examples';
		if (!fs.existsSync(root)) continue;
		for (const dir of fs.readdirSync(root).sort()) {
			const p = `${root}/${dir}`;
			if (!fs.statSync(p).isDirectory()) continue;
			const hx = fs.readdirSync(p).filter((f) => f.endsWith('.hx')).sort();
			const ts = ['main.ts', 'main.tsx'].find((f) => fs.existsSync(`${p}/${f}`));
			const alt = docs && ts && hx.length > 0 && header(`${p}/${ts}`) ? `${p}/${ts}` : '';
			const entries = ts && !alt ? [{ file: `${p}/${ts}`, entry: p, main: 'main', id: dir }]
				: hx.map((f) => {
					const main = f.slice(0, -3);
					return { file: `${p}/${f}`, entry: `${p}/${f}`, main, id: dir + (hx.length > 1 && main.toLowerCase() !== dir.replace('-', '') ? '-' + main.toLowerCase() : '') };
				});
			for (const e of entries) {
				const head = header(e.file);
				if (!head) continue;
				if (list.some((x) => x.id === e.id)) throw new Error(`site: two examples named ${e.id} (${e.file})`);
				const page = fs.existsSync(`${p}/page.json`) ? JSON.parse(fs.readFileSync(`${p}/page.json`, 'utf8')) : null;
				list.push({ ...e, dir, root, docs, alt, title: head.title, summary: head.summary ?? '', tags: (head.tags ?? '').split(',').map((t) => t.trim()).filter((t) => t),
					demo: process.env.SITE_SKIP_DATA && head.data ? null : demoOf(head.demo), apk: head.apk === 'android', data: head.data ?? null, page });
			}
		}
	}
	return list;
}

function run(args, log) {
	return new Promise((resolve) => {
		const p = spawn(process.execPath, args, { stdio: ['ignore', 'pipe', 'pipe'] });
		let text = '';
		p.stdout.on('data', (d) => (text += d));
		p.stderr.on('data', (d) => (text += d));
		p.on('close', (code) => {
			if (log) fs.writeFileSync(log, text);
			resolve({ code, text });
		});
	});
}

function copyDir(from, to) {
	fs.mkdirSync(to, { recursive: true });
	fs.cpSync(from, to, { recursive: true });
}

const t0 = Date.now();
const all = examples();
const builds = all.filter((e) => e.demo);
fs.rmSync(work, { recursive: true, force: true });
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(work, { recursive: true });

// (the CLI built once, before the builds run it in parallel)
const help = spawnSync(process.execPath, [...cli, 'help'], { encoding: 'utf8' });
if (help.status !== 0) {
	process.stderr.write(help.stdout + help.stderr);
	process.exit(1);
}

// (the files fetched at run time: each example's fetch.mjs, one at a time)
for (const e of builds.filter((e) => e.data)) {
	const r = spawnSync(process.execPath, [`${e.root}/${e.dir}/fetch.mjs`], { stdio: 'inherit' });
	if (r.status !== 0 || !fs.existsSync(`${e.root}/${e.dir}/${e.data}`)) {
		console.error(`site: ${e.id}'s ${e.root}/${e.dir}/fetch.mjs failed`);
		process.exit(1);
	}
}

const failed = [];
let next = 0;
async function worker() {
	while (next < builds.length) {
		const e = builds[next++];
		const dir = `${work}/${e.id}`;
		fs.mkdirSync(dir, { recursive: true });
		const s = Date.now();
		const r = await run([...cli, 'build', e.entry, '--target', 'web', '-o', `${dir}/${e.main}.wasm`], `${dir}.log`);
		const ok = r.code === 0 && fs.existsSync(`${dir}/${e.main}.wasm`);
		console.log(`${e.id.padEnd(22)} ${ok ? 'ok  ' : 'FAIL'} ${((Date.now() - s) / 1000).toFixed(1).padStart(6)}s`);
		if (!ok) {
			failed.push(e.id);
			console.log(r.text.slice(-1500));
		}
	}
}
await Promise.all(Array.from({ length: Math.max(1, Math.min(4, os.availableParallelism() - 1)) }, worker));
if (failed.length) {
	console.error(`site: ${failed.join(', ')} failed to build`);
	process.exit(1);
}

// the layout: each build's module and assets, the browser modules and fonts shared
const site = [];
for (const e of all) {
	const item = { id: e.id, title: e.title, summary: e.summary, tags: e.tags, source: `${REPO}/tree/main/${e.root}/${e.dir}`,
		demo: e.demo, wasm: '', imports: [], fonts: [], assets: '', apk: null, args: [], page: null, dataBytes: 0,
		docs: e.docs, file: e.file, alt: e.alt, dir: `${e.root}/${e.dir}` };
	if (e.page) item.page = { description: e.page.description ?? [], compare: e.page.compare ?? [], devices: (e.page.devices ?? []).map((d) => ({ fetchedGzMB: '–', ...d })), credits: e.page.credits ?? [],
		numbers: e.page.numbers ?? [], seconds: e.page.seconds ?? 0 };
	if (e.apk && process.env.SITE_APK) {
		// (arm64, a phone's; signed with the key HELDER_ANDROID_KEY names when it is set, else helder's cached one)
		const file = `examples/apk/${e.id}.apk`;
		fs.mkdirSync(`${out}/examples/apk`, { recursive: true });
		const r = await run([...cli, 'build', e.entry, '--target', 'android', '-o', `${out}/${file}`], `${work}/${e.id}-apk.log`);
		if (r.code !== 0 || !fs.existsSync(`${out}/${file}`)) {
			console.error(`site: ${e.id}'s APK failed to build\n` + r.text.slice(-1500));
			process.exit(1);
		}
		const commit = (process.env.GITHUB_SHA ?? spawnSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).stdout ?? '').trim().slice(0, 7);
		item.apk = { file, bytes: fs.statSync(`${out}/${file}`).size, commit };
		console.log(`${(e.id + ' (apk)').padEnd(22)} ok   ${(item.apk.bytes / 1048576).toFixed(1)} MB`);
	}
	if (e.demo) {
		const dir = `${work}/${e.id}`, dest = `${out}/examples/${e.id}`;
		fs.mkdirSync(dest, { recursive: true });
		fs.copyFileSync(`${dir}/${e.main}.wasm`, `${dest}/${e.main}.wasm`);
		item.wasm = `examples/${e.id}/${e.main}.wasm`;
		if (e.data) {
			// (only the data files: the fetch's metadata and references stay out,
			// and a .glb packed into .hxm3d files, which the program reads instead)
			fs.mkdirSync(`${dest}/${e.data}`, { recursive: true });
			const files = fs.readdirSync(`${e.root}/${e.dir}/${e.data}`);
			for (const f of files.filter((f) => /\.(glb|hxm3d|ktx2|bin)$/.test(f) && !(f.endsWith('.glb') && files.includes(f.slice(0, -4) + '.hxm3d')))) {
				fs.copyFileSync(`${e.root}/${e.dir}/${e.data}/${f}`, `${dest}/${e.data}/${f}`);
				item.dataBytes += fs.statSync(`${dest}/${e.data}/${f}`).size;
			}
			item.args = [`examples/${e.id}/${e.data}/`];
		}
		const listed = `${dir}/${e.main}.wasm.assets.json`;
		if (fs.existsSync(listed) && JSON.parse(fs.readFileSync(listed, 'utf8')).length > 0) {
			fs.copyFileSync(listed, `${dest}/${e.main}.wasm.assets.json`);
			copyDir(`${dir}/assets`, `${dest}/assets`);
			item.assets = `${item.wasm}.assets.json`;
		}
		// (the packages whose browser modules the build put beside it: Page.hx's)
		for (const p of fs.readdirSync(`${dir}/helder`).sort()) {
			copyDir(`${dir}/helder/${p}`, `${out}/static/helder/${p}`);
			if (fs.existsSync(`${dir}/helder/${p}/imports.mjs`)) item.imports.push(`static/helder/${p}/imports.mjs`);
		}
		if (fs.existsSync(`${dir}/fonts`)) for (const f of fs.readdirSync(`${dir}/fonts`).sort()) {
			fs.mkdirSync(`${out}/static/fonts`, { recursive: true });
			fs.copyFileSync(`${dir}/fonts/${f}`, `${out}/static/fonts/${f}`);
			item.fonts.push(`static/fonts/${f}`);
		}
	}
	site.push(item);
}
// the pages' sheet, scripts and fonts (helder studio's type, as helder.build's)
fs.mkdirSync(`${out}/static/fonts`, { recursive: true });
fs.copyFileSync('src/helder/web/loader.js', `${out}/static/loader.js`);
for (const f of ['site.css', 'stage.js', 'numbers.js', 'docs.js']) fs.copyFileSync(`site/${f}`, `${out}/static/${f}`);
for (const f of ['HankenGrotesk-Regular.ttf', 'HankenGrotesk-Medium.ttf', 'GeistMono-Regular.ttf']) fs.copyFileSync(`apps/studio/fonts/${f}`, `${out}/static/fonts/${f}`);
fs.writeFileSync(`${out}/index.html`, '<!doctype html>\n<meta charset="utf-8">\n<meta http-equiv="refresh" content="0; url=examples/">\n<title>helder</title>\n<a href="examples/">Examples</a>\n');
// the videos site/reel.mjs records into <out>/examples/media after this (the showreel first): each clip's example
const clips = CLIPS.map((c) => {
	const e = site.find((x) => x.source.endsWith('/' + c.entry));
	return { id: c.id, example: e ? e.id : '', title: e ? e.title : c.id, summary: e ? e.summary : '', video: `examples/media/${c.id}.mp4`, poster: `examples/media/${c.id}.jpg`,
		seconds: c.seconds };
});
fs.writeFileSync(`${work}/examples.json`, JSON.stringify({ dir: out, repository: REPO, examples: site, clips, theme }, null, '\t') + '\n');

// the page: index.tsx built natively, then run
// (.exe on Windows: the build names its output so)
const exe = process.platform === 'win32' ? '.exe' : '';
const page = await run([...cli, 'build', 'site/index.tsx', '-o', `${work}/page${exe}`], `${work}/page.log`);
if (page.code !== 0) {
	console.error(page.text);
	process.exit(1);
}
const r = spawnSync(path.resolve(`${work}/page${exe}`), [], { stdio: 'inherit' });
if (r.status !== 0 || !fs.existsSync(`${out}/examples/index.html`)) {
	console.error('site: the page did not write ' + out + '/examples/index.html');
	process.exit(1);
}

// the docs (docs/: site/docs/Docs.hx, helder.web's static renderer on the
// Markdown pages, their examples the builds above): built natively, then run
const docs = await run([...cli, 'build', 'site/docs/Docs.hx', '-o', `${work}/docs${exe}`], `${work}/docs.log`);
if (docs.code !== 0) {
	console.error(docs.text);
	process.exit(1);
}
const d = spawnSync(path.resolve(`${work}/docs${exe}`), [out], { stdio: 'inherit' });
if (d.status !== 0) {
	console.error('site: the docs failed (bin/site-build/docs ' + out + ')');
	process.exit(1);
}
console.log(`site: ${out}/examples, ${site.filter((e) => !e.docs).length} examples (${builds.filter((e) => !e.docs).length} playable), ${out}/docs, ${((Date.now() - t0) / 1000).toFixed(0)}s`);
