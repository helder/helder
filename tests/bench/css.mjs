// helder.css against lightningcss (napi, a pinned devDependency) on the
// same real stylesheets (tests/css/sheets.mjs), the bench css lane: MB/s,
// the least of RUNS (10) after a warm-up, into bin/bench/css.md.
//
// What each side does differs, and the table says so: helder.css's
// "tokens" is Syntax 3's tokenizer alone; its "sheet" tokenizes and
// parses into rules, declarations and component values (no property
// grammar). lightningcss's JavaScript API has no parse-only call: its
// transform (minify off, no targets, error recovery on) parses each
// property into typed values and prints the sheet back, both measured
// together in-process (its Rust StyleSheet::parse would be the parse
// alone).
//
//   node tests/bench/css.mjs <CssBench executable> <CssBench.wasm>
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { transform } from 'lightningcss';
import { fetchSheets } from '../css/sheets.mjs';

const [native, wasm] = process.argv.slice(2);
const runs = Number(process.env.RUNS ?? 10);
const sheets = await fetchSheets();
const ours = (cmd, args) =>
	execFileSync(cmd, args, { encoding: 'utf8', env: { ...process.env, RUNS: String(runs) }, maxBuffer: 1 << 26 })
		.trim()
		.split('\n')
		.filter((l) => l.startsWith('{'))
		.map((l) => JSON.parse(l));
const rel = sheets.map((f) => path.relative(process.cwd(), f));
const results = [...ours(native, rel).map((r) => ({ ...r, side: 'native' }))];
if (wasm) results.push(...ours(process.execPath, ['--stack-size=65500', 'tests/wasi.mjs', wasm, ...rel]).map((r) => ({ ...r, side: 'wasm32-wasi' })));
for (const f of sheets) {
	const code = fs.readFileSync(f), name = path.basename(f);
	const run = () => transform({ filename: name, code, minify: false, errorRecovery: true });
	run();
	let best = Infinity;
	for (let k = 0; k < runs; k++) {
		const t = performance.now();
		run();
		best = Math.min(best, performance.now() - t);
	}
	results.push({ sheet: name, bytes: code.length, phase: 'parse + print', ms: best, side: 'lightningcss 1.33.0 (napi)' });
}

const mbs = (r) => (r.bytes / 1e6 / (r.ms / 1000)).toFixed(1);
const cols = [
	['native', 'tokens'],
	['native', 'sheet'],
	['wasm32-wasi', 'tokens'],
	['wasm32-wasi', 'sheet'],
	['lightningcss 1.33.0 (napi)', 'parse + print'],
].filter(([s]) => results.some((r) => r.side === s));
const head = cols.map(([s, p]) => `${s === 'native' || s === 'wasm32-wasi' ? `helder.css ${s}` : s}: ${p}`);
const lines = [
	`| sheet | KB | ${head.join(' | ')} |`,
	`| --- | ---: | ${cols.map(() => '---:').join(' | ')} |`,
];
for (const f of sheets) {
	const name = path.basename(f), size = fs.statSync(f).size;
	const cell = ([s, p]) => {
		const r = results.find((x) => x.sheet === name && x.side === s && x.phase === p);
		return r ? `${mbs(r)} MB/s (${r.ms.toFixed(1)} ms)` : '';
	};
	lines.push(`| ${name} | ${Math.round(size / 1024)} | ${cols.map(cell).join(' | ')} |`);
}
const table = lines.join('\n');
const md = `# helder.css bench\n\nThe least of ${runs} runs after a warm-up, MB/s of the sheet's bytes (${process.platform}-${process.arch}, node ${process.version}).\n\n${table}\n\n- helder.css tokens: Syntax 3's tokenizer alone (Css.tokens).\n- helder.css sheet: tokenized and parsed into rules, declarations and component values (Css.sheet), no property grammar.\n- lightningcss parse + print: transform, minify off, no targets, error recovery on: every property parsed into typed values, then printed; its JavaScript API has no parse-only call.\n`;
fs.mkdirSync('bin/bench', { recursive: true });
fs.writeFileSync('bin/bench/css.md', md);
console.log(md);
