// helder.dom against parse5 (the pinned devDependency, scripting off): the
// same tree, in html5lib's format, for generated markup (seeded: the same
// documents every run) and real pages (the repository's, and the bench's
// when bin/bench/html has them). The tree construction tests' inputs are
// not among them: dom-conformance checks those against WPT's trees, and
// parse5 differs from a few (<search> in the lists of block elements, a
// frameset after a template, CDATA in integration points).
//
// parse5 8.1.1 predates two changes of the HTML standard that helder.dom
// follows, content inside <select> and processing instructions: inputs with
// "<select" or "<?" are left out and counted. Its other differences from the
// standard are listed in tests/dom/parse5-known.json, each generated
// document that shows one with what it is and its smallest form (each
// checked by hand against the standard's text): one not listed fails, and
// so does one listed that no longer differs.
//
//   node tests/dom/parse5.mjs bin/dom/DomDump [count]
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { parse } from 'parse5';

const [dumper, countArg] = process.argv.slice(2);
if (!dumper) throw new Error('usage: node tests/dom/parse5.mjs <DomDump> [count]');
const count = Number(countArg ?? 5000);
const known = JSON.parse(fs.readFileSync('tests/dom/parse5-known.json', 'utf8')).documents;
const out = 'bin/dom/parse5';
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });

// (a small seeded generator: mulberry32)
let seed = 0x5eed;
const random = () => {
	seed = (seed + 0x6d2b79f5) | 0;
	let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
	t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
	return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const pick = (a) => a[Math.floor(random() * a.length)];

const TAGS = `html head body title meta link base style script noscript template frameset frame noframes p div span a b i u s em strong small big nobr font code tt
	table caption colgroup col tbody thead tfoot tr td th form input button textarea label fieldset legend ul ol li dl dt dd h1 h2 h3 h4 h5 h6 pre listing
	plaintext xmp iframe noembed object applet marquee embed img image br hr wbr area param source track keygen address article aside blockquote center
	details dialog dir figcaption figure footer header hgroup main menu nav search section summary ruby rb rt rtc rp math mi mo mn ms mtext mglyph malignmark
	annotation-xml svg foreignObject desc circle path g lineargradient clippath sarcasm x-y isindex`.split(/\s+/);
const TEXT = ['a', ' ', '\n', '\r\n', '\t', 'x y', '&amp;', '&amp', '&notin;', '&notit;', '&#x41;', '&#128;', '&#0;', '&#xD800;', '&lt;', '&;', '&', '<', '>', '\0', 'é', '\u{1F600}', '"', "'", '=', '-->', ']]>'];
const ATTRS = ['id', 'class', 'type', 'title', 'xlink:href', 'xml:lang', 'xmlns', 'definitionurl', 'viewbox', 'encoding', 'color', 'size', 'face', 'href', 'A', 'x"'];
const VALUES = ['', 'hidden', 'text/html', 'application/xhtml+xml', 'a b', '&amp;', '"', "'", '<>', 'x'];

function attrs() {
	let s = '';
	for (let k = Math.floor(random() * 3); k > 0; k--) {
		const name = pick(ATTRS), v = pick(VALUES);
		s += pick([' ', '\n', '/']) + name + pick(['', `="${v.replace(/"/g, '')}"`, `='${v.replace(/'/g, '')}'`, `=${v.replace(/[\s"'=<>`]/g, '') || 'v'}`]);
	}
	return s;
}

function token() {
	switch (Math.floor(random() * 12)) {
		case 0: case 1: case 2: case 3: return `<${pick(TAGS)}${attrs()}${random() < 0.1 ? '/' : ''}>`;
		case 4: case 5: return `</${pick(TAGS)}>`;
		case 6: case 7: case 8: return pick(TEXT);
		case 9: return pick(['<!--c-->', '<!-->', '<!--a--!>', '<!-- -- -->', '<!x>', '</ x>', '<![CDATA[d]]>', '<!---->']);
		case 10: return pick(['<!doctype html>', '<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">', '<!doctype x>', '<!doctype>', '<!DOCTYPE html SYSTEM "about:legacy-compat">']);
		default: return pick(['<table>', '<tr>', '<td>', '</table>', '<svg>', '</svg>', '<math>', '<template>', '</template>', '<p>', '<a>', '<b>']);
	}
}

const docs = [];
for (let i = 0; i < count; i++) {
	let s = '';
	for (let k = 1 + Math.floor(random() * 40); k > 0; k--) s += token();
	docs.push([`gen-${i}`, s]);
}
const real = ['src/helder/cli/page.html', 'apps/studio/web/index.html'];
if (fs.existsSync('bin/bench/html')) for (const f of fs.readdirSync('bin/bench/html')) if (f.endsWith('.html')) real.push(`bin/bench/html/${f}`);
for (const f of real) if (fs.existsSync(f)) docs.push([path.basename(f, '.html'), fs.readFileSync(f, 'utf8')]);
const skipped = docs.filter(([, s]) => /<select|<\?/i.test(s)).length;
const compared = docs.filter(([, s]) => !/<select|<\?/i.test(s));
const files = compared.map(([name, s]) => {
	const file = `${out}/${name}.html`;
	fs.writeFileSync(file, s);
	return file;
});
// (a failed dump explains itself: its status or signal, the tool's output,
// the document that fails, found by dumping the chunk's one at a time)
function run(chunk) {
	return spawnSync(dumper, chunk, { encoding: 'utf8', maxBuffer: 1 << 26 });
}
function said(r) {
	return `status ${r.status}, signal ${r.signal}${r.error ? `, error ${r.error.message}` : ''}\n--- stdout\n${r.stdout ?? ''}\n--- stderr\n${r.stderr ?? ''}`;
}
for (let i = 0; i < files.length; i += 500) {
	const chunk = files.slice(i, i + 500);
	const r = run(chunk);
	if (r.status === 0) continue;
	console.log(`FAILED: helder's side, ${dumper} on documents ${i} to ${i + chunk.length - 1} (${chunk[0]} ... ${chunk.at(-1)}): ${said(r)}`);
	let named = false;
	for (const f of chunk) {
		const one = run([f]);
		if (one.status === 0) continue;
		console.log(`FAILED: helder's side, ${f} alone: ${said(one)}`);
		named = true;
		break;
	}
	if (!named) console.log('FAILED: each of those documents dumps alone (a failure of that one run, not of a document)');
	process.exit(1);
}

const NS = { 'http://www.w3.org/2000/svg': 'svg ', 'http://www.w3.org/1998/Math/MathML': 'math ' };
const ATTR_NS = { 'http://www.w3.org/1999/xlink': 'xlink ', 'http://www.w3.org/XML/1998/namespace': 'xml ', 'http://www.w3.org/2000/xmlns/': 'xmlns ' };
// (Dump.hx's order: a code unit comparison of the whole line)
const order = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
function dump(root) {
	const lines = [];
	const walk = (n, depth) => {
		const pad = '| ' + '  '.repeat(depth);
		if (n.nodeName === '#text') lines.push(`${pad}"${n.value}"`);
		else if (n.nodeName === '#comment') lines.push(`${pad}<!-- ${n.data} -->`);
		else if (n.nodeName === '#documentType') lines.push(`${pad}<!DOCTYPE ${n.name}${n.publicId || n.systemId ? ` "${n.publicId}" "${n.systemId}"` : ''}>`);
		else if (n.tagName !== undefined) {
			lines.push(`${pad}<${NS[n.namespaceURI] ?? ''}${n.tagName}>`);
			const attrs = n.attrs.map((a) => `${a.namespace ? ATTR_NS[a.namespace] ?? '' : ''}${a.name}="${a.value}"`).sort(order);
			for (const a of attrs) lines.push(`${pad}  ${a}`);
			if (n.content) {
				lines.push(`${pad}  content`);
				for (const c of n.content.childNodes) walk(c, depth + 2);
			}
		}
		for (const c of n.childNodes ?? []) walk(c, depth + 1);
	};
	for (const c of root.childNodes) walk(c, 0);
	return lines.join('\n') + '\n';
}

const differ = [], seen = new Set();
compared.forEach(([name], i) => {
	let want, got;
	try {
		want = dump(parse(compared[i][1], { scriptingEnabled: false }));
	} catch (e) {
		console.log(`FAILED: parse5's side, ${files[i]}: ${e.stack}`);
		process.exit(1);
	}
	try {
		got = fs.readFileSync(files[i] + '.helder', 'utf8');
	} catch (e) {
		console.log(`FAILED: helder's side, ${files[i]}.helder not written (${e.message}) though ${dumper} exited 0`);
		process.exit(1);
	}
	if (got === want) return;
	const g = got.split('\n'), w = want.split('\n');
	let k = 0;
	while (g[k] === w[k]) k++;
	if (known[name]) {
		seen.add(name);
		return;
	}
	differ.push(`${name}: line ${k + 1}: helder ${JSON.stringify(g[k])}, parse5 ${JSON.stringify(w[k])}`);
});
for (const d of differ.slice(0, 20)) console.log('DIFFERS ' + d);
const stale = Object.keys(known).filter((k) => Number(k.slice(4)) < count && !seen.has(k));
for (const k of stale) console.log(`STALE ${k}: listed in parse5-known.json, the same tree now`);
const realCount = compared.filter(([n]) => !n.startsWith('gen-')).length;
console.log(`parse5: ${compared.length - differ.length - seen.size} of ${compared.length} documents the same tree (${compared.length - realCount} generated, ${realCount} real), ${seen.size} known differences of parse5's; ${skipped} with <select or <? left out`);
if (differ.length + stale.length > 0) process.exit(1);
