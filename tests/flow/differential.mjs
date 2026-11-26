// helder.ui.flow's inline layout against Chromium's, in Ahem (every glyph a
// square of its size: metrics exact on both sides): generated inline
// content (text in white-space's modes, nested inline boxes with padding,
// borders and margins, inline-blocks of fixed sizes, vertical-align's
// values, line heights, forced breaks, text-align and text-indent) laid
// out by headless Chromium (Playwright) and by InlineDiffCheck natively,
// each text node's Range.getClientRects, each inline box's getClientRects,
// each inline-block's border box and the block's height compared within
// 0.5px. Cases: FLOW_CASES (300) from FLOW_SEED (0), then the kept ones
// (tests/flow/fixtures/differential/*.json, KEEP=1 writes a failing
// generated case there); differential-known.json lists the kept cases that
// differ on purpose, each with its reason (a known one that passes fails
// the run, so the list stays true).
//   node tests/flow/differential.mjs <InlineDiffCheck executable>
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {playwright} from '../playwright.mjs';

const exe = process.argv[2];
const COUNT = Number(process.env.FLOW_CASES ?? 300), SEED = Number(process.env.FLOW_SEED ?? 0), KEEP = process.env.KEEP === '1';
const TOLERANCE = 0.5;
const kept = 'tests/flow/fixtures/differential', knownFile = 'tests/flow/differential-known.json';
fs.mkdirSync('bin/flow', {recursive: true});

// (mulberry32)
function random(seed) {
	let a = seed >>> 0;
	return () => {
		a = (a + 0x6D2B79F5) >>> 0;
		let t = a;
		t = Math.imul(t ^ (t >>> 15), t | 1);
		t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}

// (FLOW_NO=va,tab,...: cases without those features, to see which one a difference is about)
const NO = new Set((process.env.FLOW_NO ?? '').split(',').filter(x => x));

function generate(seed) {
	const r = random(seed * 7919 + 17);
	const int = (a, b) => a + Math.floor(r() * (b - a + 1));
	const pick = xs => xs[Math.floor(r() * xs.length)];
	let ids = 0;
	const edges = () => r() < 0.5 || NO.has('edges') ? [0, 0, 0, 0] : [int(0, 6), int(0, 6), int(0, 6), int(0, 6)];
	const valign = style => {
		if (r() < 0.4) [style.verticalAlign, style.verticalShift] = [pick(['sub', 'super', 'text-top', 'text-bottom', 'middle', 'top', 'bottom', 'length']), int(-8, 8)];
		const va = style.verticalAlign;
		if (NO.has('va') || NO.has('tb') && (va === 'top' || va === 'bottom') || NO.has('mid') && va === 'middle'
			|| NO.has('tt') && (va === 'text-top' || va === 'text-bottom') || NO.has('shift') && (va === 'sub' || va === 'super' || va === 'length'))
			style.verticalAlign = 'baseline';
	};
	const inherited = (p, own) => ({
		fontSize: own ? pick([p.fontSize, p.fontSize, 10, 16, 20, 25]) : p.fontSize,
		lineHeight: own && r() < 0.3 ? pick([null, 12, 20, 30]) : p.lineHeight,
		whiteSpace: own && r() < 0.2 ? pick(['normal', 'nowrap', 'pre-wrap', 'pre-line']) : p.whiteSpace,
		overflowWrap: p.overflowWrap,
		wordBreak: p.wordBreak,
		letterSpacing: p.letterSpacing,
		wordSpacing: p.wordSpacing,
		textAlign: p.textAlign,
		textIndent: p.textIndent,
		verticalAlign: 'baseline', verticalShift: 0,
		margin: [0, 0, 0, 0], border: [0, 0, 0, 0], padding: [0, 0, 0, 0],
	});
	const root = {
		fontSize: pick([10, 16, 20, 25]), lineHeight: pick([null, null, 16, 20, 30]),
		whiteSpace: pick(['normal', 'normal', 'normal', 'pre-wrap', 'pre-line', 'nowrap', 'pre', 'break-spaces']),
		overflowWrap: pick(['normal', 'normal', 'break-word', 'anywhere']), wordBreak: pick(['normal', 'normal', 'normal', 'break-all']),
		letterSpacing: pick([0, 0, 0, 2]), wordSpacing: pick([0, 0, 0, 5]),
		textAlign: pick(['start', 'start', 'center', 'right', 'end']), textIndent: pick([0, 0, 0, 10, -5]),
		verticalAlign: 'baseline', verticalShift: 0, margin: [0, 0, 0, 0], border: [0, 0, 0, 0], padding: [0, 0, 0, 0],
	};
	const words = () => {
		let s = '';
		for (let i = int(1, 6); i > 0; i--) {
			s += 'abcdxyz'.slice(0, int(1, 7));
			s += pick([' ', ' ', ' ', '  ', '-', '\n', NO.has('tab') ? ' ' : '\t', ' ']);
		}
		return r() < 0.2 ? ' ' + s : s;
	};
	const children = (parent, depth) => {
		const out = [];
		for (let i = int(1, depth > 1 ? 3 : 5); i > 0; i--) {
			const k = r();
			if (k < 0.5) out.push({kind: 'text', id: 't' + ids++, text: words()});
			else if (k < 0.75 && depth < 3) {
				const style = inherited(parent, true);
				style.padding = edges();
				style.border = edges().map(x => x >> 1);
				style.margin = NO.has('edges') ? [0, 0, 0, 0] : [0, int(-2, 6), 0, int(-2, 6)];
				valign(style);
				out.push({kind: 'box', id: 'b' + ids++, style, children: children(style, depth + 1)});
			} else if (k < 0.9) {
				const style = inherited(parent, false);
				style.margin = edges();
				valign(style);
				const a = {kind: 'atomic', id: 'a' + ids++, width: int(0, 60), height: int(0, 60), style};
				if (!NO.has('atomic')) out.push(a);
			} else if (!NO.has('br')) out.push({kind: 'br'});
		}
		return out;
	};
	const c = {name: `seed-${seed}`, width: int(0, 40) * 10, style: root, children: children(root, 0)};
	if (NO.has('bs') && root.whiteSpace === 'break-spaces') root.whiteSpace = 'pre-wrap';
	if (NO.has('ow')) [root.overflowWrap, root.wordBreak] = ['normal', 'normal'];
	if (NO.has('ls')) [root.letterSpacing, root.wordSpacing] = [0, 0];
	// (the root's inherited values given to every element again)
	const inherit = ns => {
		for (const n of ns)
			if (n.style) {
				if (NO.has('bs') && n.style.whiteSpace === 'break-spaces') n.style.whiteSpace = 'pre-wrap';
				if (NO.has('ow')) [n.style.overflowWrap, n.style.wordBreak] = ['normal', 'normal'];
				if (NO.has('ls')) [n.style.letterSpacing, n.style.wordSpacing] = [0, 0];
				if (n.children) inherit(n.children);
			}
	};
	inherit(c.children);
	return c;
}

// (a style as CSS, every value given)
function css(s, atomic) {
	const px = a => a.map(v => v + 'px').join(' ');
	return [`font: ${s.fontSize}px/${s.lineHeight == null ? 'normal' : s.lineHeight + 'px'} Ahem`, `white-space: ${s.whiteSpace}`,
		`overflow-wrap: ${s.overflowWrap}`, `word-break: ${s.wordBreak}`, `letter-spacing: ${s.letterSpacing}px`, `word-spacing: ${s.wordSpacing}px`,
		`text-align: ${s.textAlign}`, `text-indent: ${s.textIndent}px`,
		`vertical-align: ${s.verticalAlign === 'length' ? s.verticalShift + 'px' : s.verticalAlign}`,
		`margin: ${px(s.margin)}`, `padding: ${px(s.padding)}`, `border: solid transparent`, `border-width: ${px(s.border)}`, 'tab-size: 8',
		// (a background: an inline box Blink would cull (no fragment of its own) reports its own rectangles)
		'background: rgb(0 0 0 / 1%)',
		...(atomic ? ['display: inline-block'] : [])].join('; ');
}

async function measure(page, c) {
	return page.evaluate(([c, styles]) => {
		document.body.innerHTML = '';
		const root = document.createElement('div');
		root.setAttribute('style', styles.root + `; width: ${c.width}px; margin: 0; padding: 0; border: 0`);
		const nodes = {};
		const build = (parent, children) => {
			for (const n of children) {
				if (n.kind === 'text') parent.appendChild(nodes[n.id] = document.createTextNode(n.text));
				else if (n.kind === 'br') parent.appendChild(document.createElement('br'));
				else {
					const e = document.createElement('span');
					e.setAttribute('style', styles[n.id] + (n.kind === 'atomic' ? `; width: ${n.width}px; height: ${n.height}px; box-sizing: border-box` : ''));
					parent.appendChild(nodes[n.id] = e);
					if (n.kind === 'box') build(e, n.children);
				}
			}
		};
		build(root, c.children);
		document.body.appendChild(root);
		const o = root.getBoundingClientRect(), rects = {};
		const rel = r => [r.left - o.left, r.top - o.top, r.width, r.height];
		for (const [id, n] of Object.entries(nodes)) {
			if (n.nodeType === 3) {
				const range = document.createRange();
				range.selectNodeContents(n);
				const rs = [...range.getClientRects()].filter(r => r.width > 0).map(rel);
				if (rs.length) rects[id] = rs;
			} else if (id[0] === 'a') rects[id] = [rel(n.getBoundingClientRect())];
			else rects[id] = [...n.getClientRects()].map(rel);
		}
		return {height: o.height, rects, html: root.outerHTML};
	}, [c, styleSheet(c)]);
}

function styleSheet(c) {
	const out = {root: css(c.style, false)};
	const walk = ns => {
		for (const n of ns) {
			if (n.kind === 'box') {
				out[n.id] = css(n.style, false);
				walk(n.children);
			} else if (n.kind === 'atomic') out[n.id] = css(n.style, true);
		}
	};
	walk(c.children);
	return out;
}

// (the first difference between two measurements, or null)
function differ(a, b) {
	if (Math.abs(a.height - b.height) > TOLERANCE) return `height: chromium ${a.height}, helder ${b.height}`;
	const ids = new Set([...Object.keys(a.rects), ...Object.keys(b.rects)]);
	for (const id of ids) {
		// (a node's rectangles that touch on a line as one: where a fragment ends is each engine's own)
		const sort = rs => {
			const out = [];
			for (const r of [...(rs ?? [])].sort((p, q) => p[1] - q[1] || p[0] - q[0])) {
				const last = out[out.length - 1];
				if (last && id[0] !== 'a' && Math.abs(last[1] - r[1]) < 0.05 && Math.abs(last[3] - r[3]) < 0.05 && Math.abs(last[0] + last[2] - r[0]) < 0.05) last[2] += r[2];
				else out.push([...r]);
			}
			return out;
		};
		const x = sort(a.rects[id]), y = sort(b.rects[id]);
		const show = rs => JSON.stringify(rs.map(r => r.map(v => Math.round(v * 100) / 100)));
		if (x.length !== y.length) return `${id}: chromium ${show(x)}, helder ${show(y)}`;
		for (let i = 0; i < x.length; i++)
			if (x[i].some((v, k) => Math.abs(v - y[i][k]) > TOLERANCE)) return `${id}: chromium ${show(x)}, helder ${show(y)}`;
	}
	return null;
}

// (FLOW_ONLY=seed-12: that case alone, both sides' rectangles printed)
const ONLY = process.env.FLOW_ONLY;
const cases = [];
// (FLOW_SEEDS=3,17: those seeds)
if (ONLY) cases.push(generate(Number(ONLY.replace('seed-', ''))));
else if (process.env.FLOW_SEEDS) for (const n of process.env.FLOW_SEEDS.split(',')) cases.push(generate(Number(n)));
else for (let i = 0; i < COUNT; i++) cases.push(generate(SEED + i));
const keptCases = !ONLY && fs.existsSync(kept) ? fs.readdirSync(kept).filter(f => f.endsWith('.json')).sort().map(f => JSON.parse(fs.readFileSync(path.join(kept, f), 'utf8'))) : [];
// (a kept case in place of the generated one of its name)
const keptNames = new Set(keptCases.map(c => c.name));
for (let i = cases.length - 1; i >= 0; i--) if (keptNames.has(cases[i].name)) cases.splice(i, 1);
cases.push(...keptCases);
const known = fs.existsSync(knownFile) ? JSON.parse(fs.readFileSync(knownFile, 'utf8')) : {};

fs.writeFileSync('bin/flow/cases.json', JSON.stringify(cases));
const run = spawnSync(exe, ['bin/flow/cases.json', 'bin/flow/helder.json'], {stdio: 'inherit'});
if (run.status !== 0) throw Error('InlineDiffCheck failed');
const ours = JSON.parse(fs.readFileSync('bin/flow/helder.json', 'utf8'));

const pw = playwright();
const browser = await pw.chromium.launch();
const version = browser.version(), page = await browser.newPage();
await page.setContent('<!doctype html><html><body style="margin: 0"></body></html>');
const ahem = fs.readFileSync('tests/flow/fixtures/Ahem.ttf').toString('base64');
await page.evaluate(async b64 => {
	const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
	const f = new FontFace('Ahem', bytes.buffer);
	document.fonts.add(await f.load());
}, ahem);
console.log(`differential.mjs: chromium ${version}, ${COUNT} cases from seed ${SEED}, ${keptCases.length} kept`);

let failed = 0, knownFailed = 0, passed = 0;
const failedNames = [];
const lines = [];
for (let i = 0; i < cases.length; i++) {
	const c = cases[i], theirs = await measure(page, c), d = differ(theirs, ours[i]);
	if (ONLY) fs.writeFileSync('bin/flow/only.html', theirs.html);
	delete theirs.html;
	if (ONLY) console.log(JSON.stringify(c, null, 1), '\nchromium', JSON.stringify(theirs), '\nhelder  ', JSON.stringify(ours[i]));
	const why = known[c.name];
	if (d == null) {
		passed++;
		if (why) {
			failed++;
			lines.push(`- ${c.name}: passes, but differential-known.json says it differs (${why}): take it out`);
		}
		continue;
	}
	if (why) {
		knownFailed++;
		continue;
	}
	failed++;
	failedNames.push(c.name);
	if (lines.length < 20) lines.push(`- ${c.name} (width ${c.width}): ${d}`);
	if (KEEP && c.name.startsWith('seed-') && !keptNames.has(c.name)) {
		fs.mkdirSync(kept, {recursive: true});
		fs.writeFileSync(path.join(kept, c.name + '.json'), JSON.stringify(c) + '\n');
	}
}
await browser.close();
const report = `# helder.ui.flow against Chromium ${version}\n\n${passed} of ${cases.length} cases the same within ${TOLERANCE}px, ${knownFailed} known to differ, ${failed} failed\n\n${lines.join('\n')}\n`;
fs.writeFileSync('bin/flow/differential.md', report);
fs.writeFileSync('bin/flow/failed.json', JSON.stringify(failedNames));
console.log(report);
if (failed > 0) process.exit(1);
