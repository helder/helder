// helder.css against @csstools/css-tokenizer and css-parser-algorithms
// (spec-conformant, pinned devDependencies) on real stylesheets
// (sheets.mjs): every token's kind, offsets and value, and the component
// values' tree, the same; the first difference of each sheet printed. Then
// 2,000 inputs made of CSS's edges (escapes, urls, numbers, comments,
// CDO/CDC, NUL, surrogate pairs; FUZZ_SEED, 1), each compared the same way.
// A check, not a unit test (it fetches): bun run test css-differential.
//
//   node tests/css/differential.mjs <CssDump executable>
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { tokenize, TokenType } from '@csstools/css-tokenizer';
import { parseListOfComponentValues, isFunctionNode, isSimpleBlockNode, isTokenNode, isWhitespaceNode, isCommentNode } from '@csstools/css-parser-algorithms';
import { fetchSheets } from './sheets.mjs';

const dump = process.argv[2];
if (!dump) throw new Error('usage: node differential.mjs <CssDump executable>');
const out = path.resolve('bin/css/differential');
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(path.join(out, 'generated'), { recursive: true });
const PIECES = ['a', '-', '--', '_', '\\', '\\\n', '\\31 ', '\\e9', '\\\r\n', '"', "'", 'url(', 'url( "', 'URL(', 'u+', 'U+1?', '#', '#1',
	'@', '@media', '.', '+', '5', '1.5', '1e3', 'e', 'E-', '%', 'px', '/*', '*/', '/', '*', '<!--', '-->', '<!', '<', '>', '{', '}', '(', ')', '[', ']',
	';', ':', ',', '!', 'important', ' ', '\n', '\r\n', '\r', '\t', '\f', '\0', '\u00e9', '\u{1F600}', '\u0080', '\u0130', 'n', 'var(--x)'];
let seed = Number(process.env.FUZZ_SEED ?? 1);
const random = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
const generated = [];
for (let k = 0; k < 2000; k++) {
	let text = '';
	for (let n = Math.floor(random() * 40); n > 0; n--) text += PIECES[Math.floor(random() * PIECES.length)];
	const file = path.join(out, 'generated', `${k}.css`);
	fs.writeFileSync(file, text);
	generated.push(file);
}
const sheets = await fetchSheets();
fs.writeFileSync(path.join(out, 'files'), [...sheets, ...generated].join('\n'));
execFileSync(dump, [out, ...sheets], { stdio: 'inherit' });
execFileSync(dump, [path.join(out, 'generated'), ...generated], { stdio: 'inherit' });

const q = (s) => JSON.stringify(s);
// (as CssDump writes it: the integer type, the sign)
function token(t) {
	const [type, , start, end, d] = t;
	const head = `${start}\t${end}\t`;
	switch (type) {
		case TokenType.Ident:
		case TokenType.Function:
		case TokenType.AtKeyword:
		case TokenType.String:
		case TokenType.URL:
		case TokenType.Delim:
			return head + `${type}\t${q(d.value)}`;
		case TokenType.Hash:
			return head + `${type}\t${q(d.value)}\t${d.type}`;
		case TokenType.Number:
			return head + `${type}\t${String(d.value)}\t${d.type}\t${d.signCharacter ?? ''}`;
		case TokenType.Percentage:
			return head + `${type}\t${String(d.value)}\t${d.signCharacter ?? ''}`;
		case TokenType.Dimension:
			return head + `${type}\t${String(d.value)}\t${d.type}\t${d.signCharacter ?? ''}\t${q(d.unit)}`;
		case TokenType.UnicodeRange:
			return head + `${type}\t${d.startOfRange}\t${d.endOfRange}`;
		default:
			return head + type;
	}
}

// (a function's or block's close: its start, or open where the text ended first)
const closed = (t) => (t === undefined || t[0] === TokenType.EOF ? 'open' : t[2]);

function tree(nodes, lines = []) {
	for (const n of nodes) {
		if (isCommentNode(n)) continue;
		if (isWhitespaceNode(n)) {
			for (const t of n.value) if (t[0] !== TokenType.Comment) lines.push(`t\t${t[2]}`);
		} else if (isTokenNode(n)) lines.push(`t\t${n.value[2]}`);
		else if (isFunctionNode(n)) {
			lines.push(`F\t${n.name[2]}\t${q(n.getName())}`);
			tree(n.value, lines);
			lines.push(`E\t${closed(n.endToken)}`);
		} else if (isSimpleBlockNode(n)) {
			lines.push(`B\t${n.startToken[2]}`);
			tree(n.value, lines);
			lines.push(`E\t${closed(n.endToken)}`);
		}
	}
	return lines;
}

function compare(what, name, ours, theirs) {
	const n = Math.max(ours.length, theirs.length);
	for (let i = 0; i < n; i++)
		if (ours[i] !== theirs[i]) {
			console.log(`${name}: ${what} ${i} differ\n  helder.css: ${ours[i]}\n  @csstools:  ${theirs[i]}`);
			return false;
		}
	return true;
}

let failed = 0;
for (const file of [...sheets, ...generated]) {
	const name = path.basename(file), dir = path.dirname(file).endsWith('generated') ? path.join(out, 'generated') : out;
	// (NUL filtered to U+FFFD for @csstools, as Syntax 3 §3.3 filters it
	// before tokenizing: @csstools reads a NUL in an unquoted url as a
	// non-printable code point, a bad url, which css-parsing-tests'
	// component_value_list #26 says it is not; one unit for one, the
	// offsets the same)
	const css = fs.readFileSync(file, 'utf8').replace(/^﻿/, '').replace(/\0/g, '\uFFFD');
	const tokens = tokenize({ css }).filter((t) => t[0] !== TokenType.Comment && t[0] !== TokenType.EOF);
	const ours = fs.readFileSync(path.join(dir, `${name}.tokens`), 'utf8').split('\n').filter(Boolean);
	const theirs = tokens.map(token);
	let ok = compare('token', name, ours, theirs);
	if (ok) {
		const values = fs.readFileSync(path.join(dir, `${name}.values`), 'utf8').split('\n').filter(Boolean);
		const all = tokenize({ css });
		ok = compare('value line', name, values, tree(parseListOfComponentValues(all)));
	}
	if (!ok) {
		failed++;
		if (dir !== out) console.log(`  input: ${q(css)}`);
	} else if (dir === out) console.log(`${name}: ${theirs.length} tokens, the same`);
}
if (failed > 0) {
	console.log(`differential: ${failed} of ${sheets.length} sheets and ${generated.length} generated inputs differ`);
	process.exit(1);
}
console.log(`differential: ${sheets.length} sheets and ${generated.length} generated inputs, the same tokens and component values`);
