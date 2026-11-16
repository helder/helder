// Taffy's test fixtures (https://github.com/DioxusLabs/taffy, MIT) as this
// suite's JSON fixtures: each of Taffy's tests/xml/<category>/<name>__*.xml
// (a style tree and the boxes Chrome measured, generated from
// test_fixtures/<category>/<name>.html in four variants: border-box and
// content-box, ltr and rtl) into fixtures/<category>/<name>.json, one tree
// and each variant's boxes. The manifest keeps its cases' statuses: new
// fixtures are added as pending until the runner says (BLESS=1).
//
//   node tests/layout-conformance/import-taffy.mjs <taffy checkout>
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const taffy = process.argv[2];
if (!taffy) throw new Error('usage: node import-taffy.mjs <taffy checkout>');
const CATEGORIES = ['flex', 'grid', 'gridflex', 'leaf'];
const VARIANTS = ['border_box_ltr', 'border_box_rtl', 'content_box_ltr', 'content_box_rtl'];
// (set by the variant on every node, not part of the tree)
const VARIANT_ATTRS = ['direction', 'box-sizing'];
// (the base sheet's, test_base_style.css: left out)
const DEFAULTS = { position: 'relative' };
const revision = execFileSync('git', ['-C', taffy, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();

// (the generated XML's subset: elements, attributes in double quotes, text)
function parse(xml) {
	const root = { tag: '#root', attrs: {}, children: [], text: '' };
	const stack = [root];
	const re = /<(\/?)([a-zA-Z][\w-]*)((?:\s+[\w-]+="[^"]*")*)\s*(\/?)>|([^<]+)/g;
	for (let m; (m = re.exec(xml)); ) {
		if (m[5] !== undefined) {
			stack.at(-1).text += m[5];
			continue;
		}
		if (m[1]) {
			stack.pop();
			continue;
		}
		const attrs = {};
		for (const a of m[3].matchAll(/([\w-]+)="([^"]*)"/g)) attrs[a[1]] = a[2].replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
		const node = { tag: m[2], attrs, children: [], text: '' };
		stack.at(-1).children.push(node);
		if (!m[4]) stack.push(node);
	}
	return root.children[0];
}

const child = (n, tag) => n.children.find((c) => c.tag === tag);

// (keep: per node, the variant attributes that are the same in every variant: the fixture's own)
function tree(n, keep) {
	const style = {};
	const own = keep.shift();
	for (const [k, v] of Object.entries(n.attrs)) if ((!VARIANT_ATTRS.includes(k) || own.has(k)) && DEFAULTS[k] !== v) style[k] = v;
	// (gentest writes no position for Taffy's default, static: the base sheet's relative overridden)
	if (n.tag !== '#root' && n.attrs.position === undefined) style.position = 'static';
	const out = { style };
	if (n.tag !== 'div') out.tag = n.tag;
	if (n.children.length) out.children = n.children.map((c) => tree(c, keep));
	else if (n.text.trim()) out.text = n.text.trim();
	return out;
}

// (each node's variant attributes, in order)
function variantAttrs(n, out = []) {
	out.push(Object.fromEntries(VARIANT_ATTRS.map((k) => [k, n.attrs[k] ?? ''])));
	for (const c of n.children) variantAttrs(c, out);
	return out;
}

function boxes(n, out = []) {
	const num = (k) => Number(n.attrs[k]);
	out.push([num('x'), num('y'), num('width'), num('height')]);
	for (const c of n.children) boxes(c, out);
	return out;
}

const manifestPath = path.join(here, 'manifest.json');
const old = fs.existsSync(manifestPath) ? JSON.parse(fs.readFileSync(manifestPath, 'utf8')) : { cases: [] };
const kept = new Map(old.cases.map((c) => [c.id, c]));
const cases = [];
for (const category of CATEGORIES) {
	const dir = path.join(taffy, 'tests/xml', category);
	const names = [...new Set(fs.readdirSync(dir).filter((f) => f.endsWith('.xml')).map((f) => f.replace(/__\w+\.xml$/, '')))].sort();
	fs.rmSync(path.join(here, 'fixtures', category), { recursive: true, force: true });
	fs.mkdirSync(path.join(here, 'fixtures', category), { recursive: true });
	for (const name of names) {
		let input, viewport, rounding;
		const variants = {};
		const tests = VARIANTS.map((v) => parse(fs.readFileSync(path.join(dir, `${name}__${v}.xml`), 'utf8')));
		const attrs = tests.map((t) => variantAttrs(child(t, 'input').children[0]));
		const keep = attrs[0].map((a, i) => new Set(VARIANT_ATTRS.filter((k) => a[k] !== '' && attrs.every((b) => b[i][k] === a[k]))));
		for (const [i, v] of VARIANTS.entries()) {
			const test = tests[i];
			const t = tree(child(test, 'input').children[0], keep.map((k) => k));
			const vp = child(test, 'viewport').attrs;
			const s = JSON.stringify(t);
			if (input === undefined) {
				input = s;
				viewport = { width: vp.width, height: vp.height };
				rounding = test.attrs['use-rounding'] !== 'false';
			} else if (s !== input) throw new Error(`${category}/${name}: ${v}'s tree differs beyond ${VARIANT_ATTRS.join(', ')}`);
			variants[v.replace(/_/g, '-')] = boxes(child(child(test, 'expectations'), 'node'));
		}
		const id = `${category}/${name}`;
		const fixture = {
			schema: 1,
			id,
			upstream: {
				repository: 'https://github.com/DioxusLabs/taffy',
				revision,
				path: `test_fixtures/${category}/${name}.html`,
				generated: `tests/xml/${category}/${name}__<variant>.xml`,
				license: 'MIT',
			},
			viewport,
			rounding,
			tree: JSON.parse(input),
			variants,
		};
		fs.writeFileSync(path.join(here, 'fixtures', category, `${name}.json`), JSON.stringify(fixture) + '\n');
		cases.push(kept.get(id) ?? { id, fixture: `fixtures/${category}/${name}.json`, pending: { 'border-box-ltr': 'new', 'border-box-rtl': 'new' } });
	}
}
const manifest = {
	schema: 1,
	taffy_revision: revision,
	variants: ['border-box-ltr', 'border-box-rtl'],
	cases,
};
// (a case a line)
const head = JSON.stringify({ ...manifest, cases: [] }, null, '\t').replace(/\[\]\n\}$/, '[\n');
fs.writeFileSync(manifestPath, head + cases.map((c) => '\t\t' + JSON.stringify(c)).join(',\n') + '\n\t]\n}\n');
console.log(`${cases.length} fixtures from taffy ${revision}`);
