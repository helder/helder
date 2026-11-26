// Writes helder.text.hyphenation's languages from the TeX hyphenation
// patterns (hyph-utf8, github.com/hyphenation/tex-hyphen at COMMIT): each
// language's patterns and exceptions packed in a class of its own, the
// table Hyphenation reads (Languages.hx), manifest.json (the inputs'
// hashes, licences, counts) and the test fixtures: words hyphenated by the
// reference below, Liang's algorithm on the files as they are, which
// Hyphenation.test.hx checks helder's packed tries against.
//
//   node src/helder/text/hyphenation/generate.mjs   (from the repository's root)
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';

const COMMIT = '29e003ea905f6740a0d66e114db9f60b26d07516'; // tag CTAN-2024.12.31
const BASE = `https://raw.githubusercontent.com/hyphenation/tex-hyphen/${COMMIT}/hyph-utf8/tex/generic/hyph-utf8/patterns`;
// (tag, the file's, the class, its licence as the file states it, the one we take it under)
const LANGUAGES = [
	['en-us', 'en-us', 'EnUs', 'all-permissive notice (copying and modification permitted, the notice kept)'],
	['en-gb', 'en-gb', 'EnGb', 'MIT'],
	['nl', 'nl', 'Nl', 'MIT'],
	['de-1996', 'de-1996', 'De1996', 'MIT'],
	['fr', 'fr', 'Fr', 'MIT'],
	['es', 'es', 'Es', 'MIT'],
	['it', 'it', 'It', 'MIT (or LPPL 1.3)'],
	['pt', 'pt', 'Pt', 'BSD 3-clause'],
	['sv', 'sv', 'Sv', 'LPPL 1.2 or later'],
	['da', 'da', 'Da', 'MIT (or LPPL 1.3)'],
	// (Norwegian's patterns, hyph-no.tex's, with Bokmål's exceptions)
	['nb', 'nb', 'Nb', 'all-permissive notice (copying and modification permitted, the notice kept)'],
	['pl', 'pl', 'Pl', 'MIT (or LPPL 1.3)'],
];
// (left out: their licences are not permissive)
const EXCLUDED = {cs: 'GPL 2 or later'};

const root = process.cwd();
const cache = path.resolve('.cache/hyph-utf8-' + COMMIT.slice(0, 8));
const outDir = 'src/helder/text/hyphenation';
const fixtureDir = 'tests/text/fixtures/hyphenation';
fs.mkdirSync(cache, {recursive: true});

function fetch(name) {
	const file = path.join(cache, name.replace(/\//g, '_'));
	const url = `${BASE}/${name}`;
	if (!fs.existsSync(file)) {
		const r = spawnSync('curl', ['-fsSL', '--max-time', '60', url, '-o', file], {encoding: 'utf8'});
		// (a language without exceptions has no .hyp.txt)
		if (r.status !== 0) {
			if (name.endsWith('.hyp.txt')) fs.writeFileSync(file, '');
			else throw Error(url + ': ' + r.stderr);
		}
	}
	const bytes = fs.readFileSync(file);
	return {url, text: bytes.toString('utf8'), sha256: crypto.createHash('sha256').update(bytes).digest('hex')};
}

// the TeX file's header: its comment lines before the first that is not one
function header(tex) {
	const out = [];
	for (const line of tex.split('\n')) {
		if (!line.startsWith('%')) break;
		out.push(line.replace(/\s+$/, ''));
	}
	return out;
}

// typesetting's hyphenmins (TeX's \lefthyphenmin, \righthyphenmin)
function mins(lines) {
	const text = lines.join('\n');
	const t = /typesetting:\s*\n%\s*left:\s*(\d+)\s*\n%\s*right:\s*(\d+)/.exec(text);
	if (!t) throw Error('no typesetting hyphenmins');
	return [Number(t[1]), Number(t[2])];
}

// the header's copyright and licence lines, kept in the generated file (the licences ask for their notice)
function notice(lines) {
	const out = [];
	let keep = false;
	for (const l of lines) {
		const top = /^% [a-z_]+:/.test(l);
		if (top) keep = /^% (title|copyright|licence):/.test(l);
		if (keep) out.push('//' + l.slice(1));
	}
	return out;
}

function words(text) {
	return text.split(/\s+/).filter(w => w.length > 0);
}

// a pattern "a1b2c": its letters "abc" and the k+1 values between them
function parse(p) {
	let letters = '';
	const values = [0];
	for (const ch of p) {
		if (ch >= '0' && ch <= '9') values[values.length - 1] = Number(ch);
		else {
			letters += ch;
			values.push(0);
		}
	}
	return {letters, values};
}

// --- the reference: Liang's algorithm on the files as they are

function reference(patterns, exceptions, alphabet, left, right) {
	const table = new Map();
	for (const p of patterns) {
		const {letters, values} = parse(p);
		table.set(letters, values);
	}
	const exc = new Map();
	for (const e of exceptions) {
		const w = e.replace(/-/g, '');
		const pts = [];
		let k = 0;
		for (const ch of e) {
			if (ch === '-') pts.push(k);
			else k++;
		}
		exc.set(w, pts);
	}
	// (a character as the patterns know it: lower case, or none)
	const lower = ch => alphabet.has(ch) ? alphabet.get(ch) : '\u0000';
	return word => {
		const lw = [...word].map(lower).join('');
		let pts;
		if (exc.has(lw)) pts = exc.get(lw);
		else {
			const w = '.' + lw + '.';
			const v = new Array(w.length + 1).fill(0);
			for (let i = 0; i < w.length; i++)
				for (let j = i + 1; j <= w.length; j++) {
					const p = table.get(w.slice(i, j));
					if (p) for (let k = 0; k < p.length; k++) if (p[k] > v[i + k]) v[i + k] = p[k];
				}
			pts = [];
			for (let pos = 1; pos < lw.length; pos++) if (v[pos + 1] % 2 === 1) pts.push(pos);
		}
		return pts.filter(pos => pos >= left && lw.length - pos >= right);
	};
}

function show(word, pts) {
	let s = '', k = 0;
	for (const ch of word) {
		if (pts.includes(k) && k > 0) s += '-';
		s += ch;
		k++;
	}
	return s;
}

// (a seeded generator: the fixtures the same on every run)
function random(seed) {
	let s = seed >>> 0;
	return () => {
		s = (s + 0x6D2B79F5) >>> 0;
		let t = s;
		t = Math.imul(t ^ (t >>> 15), t | 1);
		t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}

// --- the packed form, which Hyphenator reads
// alphabet: each letter in lower case followed by its upper case (when it
// has one of a single character), then a space; patterns: sorted, each the
// length it shares with the one before as a character (U+0001 plus it,
// at most 30) then the rest of its TeX form; exceptions: as the file has
// them (hyphens where they break), separated by spaces.

function pack(patterns) {
	const sorted = [...new Set(patterns)].sort();
	let prev = '', out = '';
	for (const p of sorted) {
		let n = 0;
		while (n < 30 && n < prev.length && n < p.length && prev[n] === p[n]) n++;
		out += String.fromCharCode(1 + n) + p.slice(n);
		prev = p;
	}
	return out;
}

// (a Haxe string literal: JSON's escapes, a backspace and a form feed as \u ones, which Haxe reads)
function literal(s) {
	const parts = [];
	const haxe = t => JSON.stringify(t).replace(/\\([bf])/g, (_, e) => e === 'b' ? '\\u0008' : '\\u000c');
	for (let i = 0; i < s.length; i += 2048) parts.push(haxe(s.slice(i, i + 2048)));
	return parts.length === 0 ? '""' : parts.join('\n\t\t\t+ ');
}

// the hand lists: words and where a reader expects them broken (checked against the reference too)
const HAND = JSON.parse(fs.readFileSync(path.join(fixtureDir, 'hand.json'), 'utf8'));

const manifest = {source: `github.com/hyphenation/tex-hyphen ${COMMIT} (CTAN-2024.12.31), hyph-utf8/tex/generic/hyph-utf8/patterns`, languages: {}, excluded: EXCLUDED};
const table = [];
fs.mkdirSync(fixtureDir, {recursive: true});
for (const [tag, file, cls, licence] of LANGUAGES) {
	const tex = fetch(`tex/hyph-${file}.tex`), pat = fetch(`txt/hyph-${file}.pat.txt`), hyp = fetch(`txt/hyph-${file}.hyp.txt`);
	const head = header(tex.text);
	// (Norwegian Bokmål's file holds its exceptions; its patterns, hyph-no's, are in its .pat.txt: the notice of both)
	const more = tag === 'nb' ? header(fetch('tex/hyph-no.tex').text) : [];
	const [left, right] = mins(head);
	const patterns = words(pat.text), exceptions = words(hyp.text);
	// (every letter of the patterns and exceptions, lower case, with its upper case)
	const letters = new Set();
	for (const p of patterns) for (const ch of parse(p).letters) if (ch !== '.') letters.add(ch);
	for (const e of exceptions) for (const ch of e) if (ch !== '-') letters.add(ch);
	const lowerOf = new Map();
	let alphabet = '';
	for (const ch of [...letters].sort()) {
		lowerOf.set(ch, ch);
		const up = ch.toUpperCase();
		alphabet += ch;
		if (up !== ch && up.length === 1 && !letters.has(up)) {
			alphabet += up;
			lowerOf.set(up, ch);
		}
		alphabet += ' ';
	}
	if (letters.size > 250) throw Error(tag + ': more letters than a trie node takes');
	const packed = pack(patterns);
	const lines = [
		'package helder.text.hyphenation;',
		'',
		`// Generated by generate.mjs (beside it) from hyph-utf8's hyph-${file} (tex-hyphen ${COMMIT.slice(0, 8)}):`,
		`// ${patterns.length} patterns, ${exceptions.length} exceptions; taken under ${licence}. Its notice:`,
		...notice(head),
		...(more.length ? ['// The patterns, hyph-no.tex\'s:', ...notice(more)] : []),
		`class ${cls} {`,
		`	public static function patterns():Patterns`,
		`		return new Patterns(${JSON.stringify(tag)}, ${left}, ${right}, ${literal(alphabet)},`,
		`			${literal(packed)},`,
		`			${literal(exceptions.join(' '))});`,
		'}',
		'',
	];
	fs.writeFileSync(path.join(outDir, cls + '.hx'), lines.join('\n'));
	table.push({tag, cls});
	manifest.languages[tag] = {
		licence, left, right, patterns: patterns.length, exceptions: exceptions.length, letters: letters.size, packed: Buffer.byteLength(packed),
		files: Object.fromEntries([['tex', tex], ['pat', pat], ['hyp', hyp]].map(([k, f]) => [k, {url: f.url, sha256: f.sha256}])),
	};

	// the fixture: the exceptions, the hand list, then words made of the patterns' own pieces
	const hyph = reference(patterns, exceptions, lowerOf, left, right);
	const rnd = random(tag.split('').reduce((a, c) => a * 31 + c.charCodeAt(0), 7));
	const pieces = patterns.map(p => parse(p).letters.replace(/\./g, '')).filter(s => s.length > 1 && [...s].every(ch => /\p{L}/u.test(ch)));
	const list = new Set(exceptions.map(e => e.replace(/-/g, '')));
	const hand = HAND[tag] ?? [];
	for (const h of hand) {
		const w = h.replace(/-/g, '');
		const got = show(w, hyph(w));
		if (got !== h) throw Error(`${tag}: the reference hyphenates ${w} as ${got}, the hand list ${h}`);
		list.add(w);
	}
	while (list.size < exceptions.length + hand.length + 300) {
		let w = '';
		const n = 2 + Math.floor(rnd() * 3);
		for (let i = 0; i < n; i++) w += pieces[Math.floor(rnd() * pieces.length)];
		// (some capitalised, as a sentence's first word)
		if (rnd() < 0.1) w = w[0].toUpperCase() + w.slice(1);
		list.add(w);
	}
	const fixture = [...list].map(w => show(w, hyph(w)));
	fs.writeFileSync(path.join(fixtureDir, tag + '.txt'), fixture.join('\n') + '\n');
	console.log(tag, {patterns: patterns.length, exceptions: exceptions.length, letters: letters.size, packed: Buffer.byteLength(packed), left, right});
}

const registry = [
	'package helder.text.hyphenation;',
	'',
	'// Generated by generate.mjs (beside it): every language helder has patterns',
	'// for (Hyphenation.addAll(): all of them in the build).',
	'class Languages {',
	`	public static final TAGS = [${table.map(t => JSON.stringify(t.tag)).join(', ')}];`,
	'',
	'	public static function all():Array<Patterns>',
	`		return [${table.map(t => t.cls + '.patterns()').join(', ')}];`,
	'}',
	'',
];
fs.writeFileSync(path.join(outDir, 'Languages.hx'), registry.join('\n'));
fs.writeFileSync(path.join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
