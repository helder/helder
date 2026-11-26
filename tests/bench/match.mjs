// helder.css's selector matching, before and after the rule index and
// Bloom filter (the bench match lane): tests/bench/MatchBench.hx natively
// on two pages fetched into bin/bench/html (as the bench html lane does),
// each against the sheets it links (fetched live from its site, so not
// pinned), a browser's UA sheet (Chromium's html.css at a release tag) and
// Bootstrap (tests/css/sheets.mjs). A table in bin/bench/match.md.
//
//   node tests/bench/match.mjs <MatchBench executable>
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fetchSheets } from '../css/sheets.mjs';

const [bench] = process.argv.slice(2);
if (!bench) throw new Error('usage: node match.mjs <MatchBench executable>');
const UA = 'https://raw.githubusercontent.com/chromium/chromium/130.0.6723.58/third_party/blink/renderer/core/html/resources/html.css';
const PAGES = {
	'html-spec': {
		url: 'https://html.spec.whatwg.org/',
		sheets: ['https://resources.whatwg.org/standard-shared-with-dev.css', 'https://resources.whatwg.org/standard.css', 'https://resources.whatwg.org/spec.css', 'https://html.spec.whatwg.org/styles.css'],
	},
	wikipedia: {
		url: 'https://en.wikipedia.org/wiki/World_War_II',
		sheets: [
			'https://en.wikipedia.org/w/load.php?lang=en&modules=ext.cite.parsoid.styles%7Cext.cite.styles%7Cext.uls.interlanguage%7Cjquery.makeCollapsible.styles%7Cmediawiki.skins.legacy%7Cskins.vector.icons%2Cstyles%7Cskins.vector.search.codex.styles%7Cwikibase.client.init&only=styles&skin=vector-2022',
			'https://en.wikipedia.org/w/load.php?lang=en&modules=site.styles&only=styles&skin=vector-2022',
		],
	},
};

async function get(url, file) {
	if (fs.existsSync(file)) return file;
	const res = await fetch(url, { headers: { 'user-agent': 'helder-bench' } });
	if (!res.ok) throw new Error(`${url}: ${res.status}`);
	fs.mkdirSync(path.dirname(file), { recursive: true });
	fs.writeFileSync(file, Buffer.from(await res.arrayBuffer()));
	return file;
}

const dir = 'bin/bench/match';
const ua = await get(UA, `${dir}/chromium-html.css`);
const bootstrap = (await fetchSheets()).find((f) => f.endsWith('bootstrap.css'));
const rows = [];
for (const [name, p] of Object.entries(PAGES)) {
	const page = await get(p.url, `bin/bench/html/${name}.html`);
	const sheets = [ua];
	for (const [k, url] of p.sheets.entries()) sheets.push(await get(url, `${dir}/${name}-${k}.css`));
	sheets.push(bootstrap);
	const out = execFileSync(bench, [page, ...sheets], { encoding: 'utf8', maxBuffer: 1 << 26 });
	for (const l of out.trim().split('\n')) if (l.startsWith('{')) rows.push(JSON.parse(l));
}

const pct = (a, b) => (b === 0 ? '' : `${((100 * a) / b).toFixed(1)}%`);
const lines = ['| page | elements | selectors | way | ms | selectors tried | rejected by the Bloom filter | matches |', '| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: |'];
for (const r of rows) {
	const tried = r.visited - r.rejected;
	lines.push(`| ${r.page} | ${r.elements} | ${r.selectors} | ${r.way} | ${r.ms} | ${tried} (${pct(tried, r.elements * r.selectors)} of all pairs) | ${r.rejected ? `${r.rejected} (${pct(r.rejected, r.visited)} of the index's)` : ''} | ${r.matched} |`);
}
const md = `# helder.css matching bench\n\nEvery element of each page against the selectors of its sheets, Chromium's UA sheet and Bootstrap, natively (${process.platform}-${process.arch}). "each selector": every selector tried on every element (no index, run once); "index": the rule index's buckets, the least of 5; "index and Bloom filter": the same during a tree walk, the ancestors' filter rejecting before matching.\n\n${lines.join('\n')}\n`;
fs.mkdirSync('bin/bench', { recursive: true });
fs.writeFileSync('bin/bench/match.md', md);
console.log(md);
