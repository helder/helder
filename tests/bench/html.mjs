// helder.dom's parse against the fastest parsers at hand (bench html), each
// on the same files, the least time of RUNS (5): helder natively and as
// wasm32-wasi (node's WASI), @lukeed/html (the fastest JavaScript parser,
// on node; it recovers from bad markup its own way, as htmlparser2 does,
// not the HTML standard's) and lexbor (a C parser that follows the
// standard's algorithm: fetched at the revision below into bin/bench/lexbor
// and built by cc, where there is one). Inputs fetched into bin/bench/html:
// the HTML standard as one page, a long Wikipedia article, and a generated
// document, deep and wide. A table in bin/bench/html.md.
//
//   node tests/bench/html.mjs bin/bench/HtmlBench bin/bench/HtmlBench.wasm
import fs from 'node:fs';
import { execFileSync, spawnSync } from 'node:child_process';
// (a stale node_modules, after a rebase: said plainly, not as node's stack)
const { parse } = await import('@lukeed/html').catch(() => {
	console.error('@lukeed/html missing: run bun install');
	process.exit(1);
});

const [native, wasm] = process.argv.slice(2);
const RUNS = Number(process.env.RUNS ?? 5);
const LEXBOR = { url: 'https://github.com/lexbor/lexbor', revision: 'b9f180a3c5f8ee7f63d55ea3585cbf9a37d16909' };
const dir = 'bin/bench/html';
fs.mkdirSync(dir, { recursive: true });

const pages = [
	['html-spec', 'https://html.spec.whatwg.org/'],
	['wikipedia', 'https://en.wikipedia.org/wiki/World_War_II'],
];
for (const [name, url] of pages) {
	const file = `${dir}/${name}.html`;
	if (fs.existsSync(file)) continue;
	const res = await fetch(url, { headers: { 'user-agent': 'helder-bench' } });
	if (!res.ok) throw new Error(`${url}: ${res.status}`);
	fs.writeFileSync(file, Buffer.from(await res.arrayBuffer()));
}
// (deep: 5,000 nested elements; wide: 50,000 paragraphs with attributes, references and inline markup)
const generated = `${dir}/generated.html`;
if (!fs.existsSync(generated)) {
	let s = '<!doctype html><title>generated</title>';
	for (let i = 0; i < 5000; i++) s += `<div class="d${i % 7}">${i}`;
	for (let i = 0; i < 5000; i++) s += '</div>';
	for (let i = 0; i < 50000; i++) s += `<p id=p${i} class="a b" data-n="${i}">Text ${i} &amp; <b>bold</b>, <a href="/x?a=1&amp;b=2">a link</a> &mdash; <i>em</i></p>\n`;
	fs.writeFileSync(generated, s);
}
const files = ['html-spec', 'wikipedia', 'generated'].map((n) => `${dir}/${n}.html`);
const size = (f) => fs.statSync(f).size;

const results = {};
const add = (tool, f, ms) => ((results[tool] ??= {})[f] = ms);
for (const line of execFileSync(native, [String(RUNS), ...files], { encoding: 'utf8' }).trim().split('\n')) {
	const r = JSON.parse(line);
	add('helder (native)', r.file, r.ms);
}
for (const line of execFileSync(process.execPath, ['--stack-size=65500', 'tests/wasi.mjs', wasm, String(RUNS), ...files], { encoding: 'utf8' }).trim().split('\n')) {
	const r = JSON.parse(line);
	add('helder (wasm32-wasi, node)', r.file, r.ms);
}
for (const f of files) {
	const html = fs.readFileSync(f, 'utf8');
	let best = Infinity;
	for (let i = 0; i < RUNS; i++) {
		const t = performance.now();
		parse(html);
		best = Math.min(best, performance.now() - t);
	}
	add('@lukeed/html (node; not the standard\'s recovery)', f, Math.round(best * 1000) / 1000);
}

// (lexbor: fetched and built once, by cc; none where there is no compiler)
let lexborNote = '';
const lexbor = 'bin/bench/lexbor';
if (spawnSync('cc', ['--version']).status === 0) {
	if (!fs.existsSync(`${lexbor}/bench`)) {
		fs.mkdirSync(`${lexbor}/src`, { recursive: true });
		const git = (...a) => execFileSync('git', ['-C', `${lexbor}/src`, ...a]);
		if (!fs.existsSync(`${lexbor}/src/.git`)) {
			git('init', '-q');
			git('remote', 'add', 'origin', LEXBOR.url);
		}
		git('fetch', '-q', '--depth', '1', 'origin', LEXBOR.revision);
		git('checkout', '-q', LEXBOR.revision);
		const sources = execFileSync('find', [`${lexbor}/src/source/lexbor`, '-name', '*.c', '-not', '-path', '*windows_nt*'], { encoding: 'utf8' }).trim().split('\n');
		execFileSync('cc', ['-O2', '-DLEXBOR_STATIC', '-I', `${lexbor}/src/source`, '-I', `${lexbor}/src/source/lexbor/ports/posix`, ...sources, 'tests/bench/lexbor.c', '-o', `${lexbor}/bench`]);
	}
	for (const line of execFileSync(`${lexbor}/bench`, [String(RUNS), ...files], { encoding: 'utf8' }).trim().split('\n')) {
		const r = JSON.parse(line);
		add('lexbor (C, -O2)', r.file, r.ms);
	}
} else lexborNote = '\n\nlexbor: not run (no cc to build it).';

const mbs = (f, ms) => (size(f) / 1e6 / (ms / 1000)).toFixed(1);
const head = `| parser | ${files.map((f) => `${f.split('/').pop()} (${(size(f) / 1e6).toFixed(1)} MB)`).join(' | ')} |`;
const rows = Object.entries(results).map(([tool, r]) => `| ${tool} | ${files.map((f) => `${r[f]} ms, ${mbs(f, r[f])} MB/s`).join(' | ')} |`);
const table = [`html parse, the least of ${RUNS} runs (MB: the file's UTF-8 bytes)`, '', head, `|---|${files.map(() => '---').join('|')}|`, ...rows].join('\n') + lexborNote;
console.log(table);
fs.writeFileSync('bin/bench/html.md', table + '\n');
